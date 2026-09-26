import Foundation

/// A skill listed in a project's lock file, with its install and update state.
public struct ProjectSkillStatus: Identifiable, Hashable, Sendable {
    public var id: String { name }
    /// Install name, the key in the lock file.
    public let name: String
    public let locked: LockedSkill
    /// The matching skill in the library, if its source is present.
    public let skill: Skill?
    /// Installed in every skills folder of the project's agents.
    public let isInstalled: Bool
    /// Latest version available in the local source checkout.
    public let latestVersion: String?

    public var hasUpdate: Bool {
        guard let latestVersion else { return false }
        return latestVersion != locked.version
    }
}

extension SkillManager {
    public var lockStore: LockFileStore {
        LockFileStore(settings: state.settings, fileManager: fileManager)
    }

    public func project(withID id: UUID) -> Project? {
        state.projects.first { $0.id == id }
    }

    // MARK: - Project list

    /// Adds a project folder. Creates its lock file when it has none; an existing lock file is kept
    /// so the project can be restored with `syncProject`.
    @discardableResult
    public func addProject(path: String, name: String? = nil) throws -> Project {
        let url = pathResolver.expand(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SkillManagerError.folderNotFound(url.path)
        }
        if state.projects.contains(where: { $0.url.standardizedFileURL.path == url.path }) {
            throw SkillManagerError.projectExists(url.path)
        }
        let project = Project(name: name.flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent, path: url.path)
        if try lockStore.read(project: project.url) == nil {
            let lockFile = SkillLockFile(
                installMode: state.settings.defaultInstallMode,
                agents: state.settings.defaultProjectAgents
            )
            try lockStore.write(lockFile, project: project.url)
        }
        state.projects.append(project)
        try save()
        return project
    }

    /// Forgets a project. Its files, lock file and installed skills are left untouched.
    public func removeProject(id: UUID) throws {
        state.projects.removeAll { $0.id == id }
        try save()
    }

    // MARK: - Lock file

    /// The project's lock file, or a new one with the default settings when it has none.
    public func lockFile(for project: Project) throws -> SkillLockFile {
        try lockStore.read(project: project.url) ?? SkillLockFile(
            installMode: state.settings.defaultInstallMode,
            agents: state.settings.defaultProjectAgents
        )
    }

    public func projectTargets(for project: Project, lockFile: SkillLockFile) -> [SkillTarget] {
        registry.projectTargets(for: lockFile.agents, in: project.url)
    }

    // MARK: - Project skills

    /// Pins the skill at its latest version in the lock file and installs it into the project.
    public func addSkill(_ skill: Skill, to project: Project) throws {
        guard !isDisabled(skill) else { throw SkillManagerError.skillDisabled(skill.name) }
        guard let source = source(withID: skill.sourceID) else {
            throw SkillManagerError.sourceNotFound(skill.sourceID)
        }
        var lockFile = try self.lockFile(for: project)
        let version: String
        switch source.kind {
        case .git:
            version = try git.lastCommit(touching: skill.relativePath, in: directory(for: source))
        case .local:
            version = LockedSkill.localVersion
        }
        let locked = LockedSkill(source: source.location, sourceType: source.kind, path: skill.relativePath, version: version)
        lockFile.skills[skill.installName] = locked
        try lockStore.write(lockFile, project: project.url)
        try install(name: skill.installName, locked: locked, project: project, lockFile: lockFile)
    }

    /// Removes a skill from the lock file and from the project's skills folders.
    public func removeSkill(named name: String, from project: Project) throws {
        var lockFile = try self.lockFile(for: project)
        for target in projectTargets(for: project, lockFile: lockFile) {
            try installer.uninstall(name: name, from: target.directory)
        }
        lockFile.skills[name] = nil
        try lockStore.write(lockFile, project: project.url)
    }

    /// Changes which agents' folders receive the project's skills.
    public func setAgents(_ agentIDs: [String], for project: Project) throws {
        var lockFile = try self.lockFile(for: project)
        let newTargets = Set(registry.projectTargets(for: agentIDs, in: project.url).map(\.directory.path))
        for target in projectTargets(for: project, lockFile: lockFile) where !newTargets.contains(target.directory.path) {
            for name in lockFile.skills.keys {
                try installer.uninstall(name: name, from: target.directory)
            }
        }
        lockFile.agents = agentIDs
        try lockStore.write(lockFile, project: project.url)
        try syncProject(project)
    }

    public func setInstallMode(_ mode: InstallMode, for project: Project) throws {
        var lockFile = try self.lockFile(for: project)
        lockFile.installMode = mode
        try lockStore.write(lockFile, project: project.url)
        try syncProject(project)
    }

    /// Installs every skill in the lock file at its pinned version, restoring missing sources,
    /// and removes Squire-made links for skills no longer listed.
    public func syncProject(_ project: Project) throws {
        let lockFile = try self.lockFile(for: project)
        if !lockStore.exists(in: project.url) {
            try lockStore.write(lockFile, project: project.url)
        }
        for name in lockFile.skills.keys.sorted() {
            if let locked = lockFile.skills[name] {
                try install(name: name, locked: locked, project: project, lockFile: lockFile)
            }
        }
        for target in projectTargets(for: project, lockFile: lockFile) {
            for entry in installer.entries(in: target.directory) where lockFile.skills[entry] == nil {
                if case .symlink(let destination) = installer.inspect(name: entry, in: target.directory),
                   isManagedLocation(destination) {
                    try installer.uninstall(name: entry, from: target.directory)
                }
            }
        }
    }

    /// Lock file entries with their install state and the latest version in the local checkout.
    public func projectStatus(_ project: Project) throws -> [ProjectSkillStatus] {
        let lockFile = try self.lockFile(for: project)
        let targets = projectTargets(for: project, lockFile: lockFile)
        return lockFile.skills.keys.sorted().compactMap { (name: String) -> ProjectSkillStatus? in
            guard let locked = lockFile.skills[name] else { return nil }
            let source = findSource(location: locked.source)
            let skill = source.flatMap { source in
                skills.first { $0.sourceID == source.id && $0.relativePath == locked.path }
            }
            let expected = expectedDirectory(for: locked, name: name)
            let installed = !targets.isEmpty && targets.allSatisfy { (target: SkillTarget) -> Bool in
                switch installer.inspect(name: name, in: target.directory) {
                case .missing, .file:
                    return false
                case .directory:
                    return lockFile.installMode == .copy
                case .symlink(let destination):
                    return lockFile.installMode == .symlink
                        && expected.map { SkillInstaller.samePath(destination, $0) } == true
                }
            }
            return ProjectSkillStatus(
                name: name,
                locked: locked,
                skill: skill,
                isInstalled: installed,
                latestVersion: latestVersion(for: locked)
            )
        }
    }

    /// Pulls the git sources the project uses, then returns its status.
    public func checkForUpdates(_ project: Project) throws -> [ProjectSkillStatus] {
        let lockFile = try self.lockFile(for: project)
        var pulled = Set<String>()
        for locked in lockFile.skills.values where locked.sourceType == .git {
            if let source = findSource(location: locked.source), pulled.insert(source.id).inserted {
                try updateSource(id: source.id)
            }
        }
        return try projectStatus(project)
    }

    /// Moves skills to their latest version and reinstalls them. `nil` updates every skill.
    public func updateProjectSkills(_ project: Project, names: [String]? = nil) throws {
        var lockFile = try self.lockFile(for: project)
        for name in names ?? Array(lockFile.skills.keys) {
            guard var locked = lockFile.skills[name], let latest = latestVersion(for: locked) else { continue }
            locked.version = latest
            lockFile.skills[name] = locked
        }
        try lockStore.write(lockFile, project: project.url)
        try syncProject(project)
    }

    // MARK: - Helpers

    /// The version a locked skill would move to, from the local checkout.
    func latestVersion(for locked: LockedSkill) -> String? {
        guard let source = findSource(location: locked.source) else { return nil }
        switch source.kind {
        case .git:
            return try? git.lastCommit(touching: locked.path, in: directory(for: source))
        case .local:
            return LockedSkill.localVersion
        }
    }

    /// Where a locked skill is installed from, without creating anything.
    func expectedDirectory(for locked: LockedSkill, name: String) -> URL? {
        guard let source = findSource(location: locked.source) else { return nil }
        switch source.kind {
        case .git:
            return store.snapshotDirectory(sourceID: source.id, skillName: name, version: locked.version)
        case .local:
            return Self.appending(locked.path, to: directory(for: source))
        }
    }

    /// Finds the library source for a lock entry, cloning or adding it when missing.
    func resolveSource(for locked: LockedSkill) throws -> SkillSource {
        if let source = findSource(location: locked.source) {
            if source.kind == .git && !fileManager.fileExists(atPath: directory(for: source).path) {
                try updateSource(id: source.id)
            }
            return source
        }
        switch locked.sourceType {
        case .git:
            return try addGitSource(url: locked.source)
        case .local:
            return try addLocalSource(path: locked.source)
        }
    }

    func install(name: String, locked: LockedSkill, project: Project, lockFile: SkillLockFile) throws {
        let source = try resolveSource(for: locked)
        let skillDirectory: URL
        switch source.kind {
        case .git:
            skillDirectory = try store.snapshot(
                sourceID: source.id,
                skillName: name,
                relativePath: locked.path,
                version: locked.version,
                repository: directory(for: source)
            )
        case .local:
            skillDirectory = Self.appending(locked.path, to: directory(for: source))
        }
        for target in projectTargets(for: project, lockFile: lockFile) {
            try installer.install(skillDirectory, as: name, into: target.directory, mode: lockFile.installMode, replaceExisting: true)
        }
    }

    /// Whether a path is inside Squire's store or one of the library's sources.
    func isManagedLocation(_ url: URL) -> Bool {
        let roots = [paths.storeDirectory] + state.sources.map { directory(for: $0) }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    static func appending(_ relativePath: String, to root: URL) -> URL {
        relativePath.isEmpty ? root : root.appendingPathComponent(relativePath, isDirectory: true)
    }
}
