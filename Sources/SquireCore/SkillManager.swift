import Foundation

public enum SkillManagerError: Error, LocalizedError, Equatable {
    case sourceExists(String)
    case sourceNotFound(String)
    case folderNotFound(String)
    case skillDisabled(String)
    case projectExists(String)
    case projectNotFound(String)
    case skillNotInSource(name: String, source: String)

    public var errorDescription: String? {
        switch self {
        case .sourceExists(let location):
            return "\(location) is already in the library."
        case .sourceNotFound(let id):
            return "There is no source \(id)."
        case .folderNotFound(let path):
            return "The folder \(path) does not exist."
        case .skillDisabled(let name):
            return "\(name) is disabled. Enable it in the Skills list first."
        case .projectExists(let path):
            return "\(path) is already a project."
        case .projectNotFound(let path):
            return "There is no project at \(path)."
        case .skillNotInSource(let name, let source):
            return "\(name) was not found in \(source)."
        }
    }
}

/// Squire's main entry point: the library of sources and skills, tags,
/// global enablement per agent, and project skills.
///
/// Not thread safe. Callers serialize access, the app runs one operation at a time.
public final class SkillManager: @unchecked Sendable {
    public let paths: SquirePaths
    public let pathResolver: PathResolver
    public let git: GitClient
    public internal(set) var state: LibraryState
    /// Every skill found in every source, refreshed by `rescan()`.
    public private(set) var skills: [Skill] = []

    let persistence: LibraryPersistence
    let scanner: SkillScanner
    let installer: SkillInstaller
    let store: SkillStore
    let fileManager: FileManager

    public init(
        paths: SquirePaths = .standard(),
        pathResolver: PathResolver = PathResolver(),
        git: GitClient = GitClient(),
        fileManager: FileManager = .default
    ) throws {
        self.paths = paths
        self.pathResolver = pathResolver
        self.git = git
        self.fileManager = fileManager
        self.persistence = LibraryPersistence(fileURL: paths.libraryFile, fileManager: fileManager)
        self.scanner = SkillScanner(fileManager: fileManager)
        self.installer = SkillInstaller(fileManager: fileManager)
        self.store = SkillStore(root: paths.storeDirectory, git: git, fileManager: fileManager)
        self.state = try persistence.load()
        rescan()
    }

    public func save() throws {
        try persistence.save(state)
    }

    // MARK: - Agents

    public var registry: AgentRegistry {
        AgentRegistry.merging(custom: state.customAgents, paths: pathResolver)
    }

    public func setCustomAgent(_ agent: AgentDefinition) throws {
        state.customAgents.removeAll { $0.id == agent.id }
        state.customAgents.append(agent)
        try save()
    }

    public func removeCustomAgent(id: String) throws {
        state.customAgents.removeAll { $0.id == id }
        try save()
    }

    // MARK: - Settings

    /// Saves new settings. When the repositories folder changes, existing clones move to the
    /// new folder (a clone already there is kept instead) and global links are pointed at them.
    public func updateSettings(_ settings: SquireSettings) throws {
        let oldRepositories = repositoriesDirectory
        let newRepositories = Self.repositoriesDirectory(for: settings, paths: paths, resolver: pathResolver)
        guard oldRepositories.standardizedFileURL.path != newRepositories.standardizedFileURL.path else {
            state.settings = settings
            try save()
            return
        }

        // Remember which global links point into the old clones, so they can be recreated.
        let targets = registry.globalTargets(onlyInstalled: false)
        var links: [(skillID: String, target: SkillTarget)] = []
        for skill in skills where source(withID: skill.sourceID)?.kind == .git {
            for target in targets where isEnabled(skill, in: target) {
                links.append((skill.id, target))
            }
        }

        try fileManager.createDirectory(at: newRepositories, withIntermediateDirectories: true)
        for source in state.sources where source.kind == .git {
            let old = oldRepositories.appendingPathComponent(source.id, isDirectory: true)
            let new = newRepositories.appendingPathComponent(source.id, isDirectory: true)
            if fileManager.fileExists(atPath: old.path) && !fileManager.fileExists(atPath: new.path) {
                try fileManager.moveItem(at: old, to: new)
            }
        }

        state.settings = settings
        try save()
        rescan()

        for link in links {
            guard let skill = self.skill(withID: link.skillID) else { continue }
            try installer.install(skill.directory, as: skill.installName, into: link.target.directory, mode: .symlink)
        }
        try importExistingClones()
    }

    // MARK: - Sources

    /// Folder git sources are cloned into, from the settings.
    public var repositoriesDirectory: URL {
        Self.repositoriesDirectory(for: state.settings, paths: paths, resolver: pathResolver)
    }

    static func repositoriesDirectory(for settings: SquireSettings, paths: SquirePaths, resolver: PathResolver) -> URL {
        guard let path = settings.repositoriesPath?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return paths.reposDirectory
        }
        return resolver.expand(path)
    }

    /// Whether a git source's clone is missing, for example after the folder was deleted.
    /// Updating the source clones it again.
    public func isCheckoutMissing(_ source: SkillSource) -> Bool {
        source.kind == .git && !fileManager.fileExists(atPath: directory(for: source).appendingPathComponent(".git").path)
    }

    /// Adds git repositories found in the repositories folder that are not sources yet,
    /// for example ones cloned by hand. Returns the new sources.
    @discardableResult
    public func importExistingClones() throws -> [SkillSource] {
        let root = repositoriesDirectory
        guard let children = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        var imported: [SkillSource] = []
        for child in children.sorted() where !child.hasPrefix(".") {
            let folder = root.appendingPathComponent(child, isDirectory: true)
            guard fileManager.fileExists(atPath: folder.appendingPathComponent(".git").path),
                  !state.sources.contains(where: { $0.id == child }) else {
                continue
            }
            // Without an origin remote the folder is still usable, it just cannot be restored elsewhere.
            let location = (try? git.remoteURL(folder)) ?? folder.path
            if findSource(location: location) != nil { continue }
            let source = SkillSource(
                id: child,
                kind: .git,
                name: child,
                location: location,
                revision: try? git.headCommit(folder),
                lastUpdated: Date()
            )
            state.sources.append(source)
            imported.append(source)
        }
        if !imported.isEmpty {
            try save()
            rescan()
        }
        return imported
    }

    public func source(withID id: String) -> SkillSource? {
        state.sources.first { $0.id == id }
    }

    /// The folder skills of `source` are read from.
    public func directory(for source: SkillSource) -> URL {
        switch source.kind {
        case .git:
            return repositoriesDirectory.appendingPathComponent(source.id, isDirectory: true)
        case .local:
            return URL(fileURLWithPath: source.location, isDirectory: true)
        }
    }

    public func skills(in source: SkillSource) -> [Skill] {
        skills.filter { $0.sourceID == source.id }
    }

    /// Clones a git repository and adds its skills to the library.
    @discardableResult
    public func addGitSource(url: String, branch: String? = nil, name: String? = nil) throws -> SkillSource {
        let location = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if findSource(location: location) != nil {
            throw SkillManagerError.sourceExists(location)
        }
        let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? Self.repositoryName(from: location)
        var source = SkillSource(
            id: uniqueSourceID(for: displayName),
            kind: .git,
            name: displayName,
            location: location,
            branch: branch.flatMap { $0.isEmpty ? nil : $0 }
        )
        let destination = directory(for: source)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try git.clone(location, to: destination, branch: source.branch)
        source.revision = try? git.headCommit(destination)
        source.lastUpdated = Date()
        state.sources.append(source)
        try save()
        rescan()
        return source
    }

    /// Adds a folder on disk as a source. Skills are read in place.
    @discardableResult
    public func addLocalSource(path: String, name: String? = nil) throws -> SkillSource {
        let url = pathResolver.expand(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SkillManagerError.folderNotFound(url.path)
        }
        if findSource(location: url.path) != nil {
            throw SkillManagerError.sourceExists(url.path)
        }
        let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent
        let source = SkillSource(
            id: uniqueSourceID(for: displayName),
            kind: .local,
            name: displayName,
            location: url.path,
            lastUpdated: Date()
        )
        state.sources.append(source)
        try save()
        rescan()
        return source
    }

    /// Pulls a git source, or clones it again when its checkout is missing. Local sources are rescanned.
    public func updateSource(id: String) throws {
        guard let index = state.sources.firstIndex(where: { $0.id == id }) else {
            throw SkillManagerError.sourceNotFound(id)
        }
        var source = state.sources[index]
        if source.kind == .git {
            let checkout = directory(for: source)
            if fileManager.fileExists(atPath: checkout.appendingPathComponent(".git").path) {
                try git.pull(checkout)
            } else {
                try git.clone(source.location, to: checkout, branch: source.branch)
            }
            source.revision = try? git.headCommit(checkout)
        }
        source.lastUpdated = Date()
        state.sources[index] = source
        try save()
        rescan()
    }

    /// Updates every source and returns the failures by source id.
    @discardableResult
    public func updateAllSources() -> [String: Error] {
        var failures: [String: Error] = [:]
        for source in state.sources {
            do {
                try updateSource(id: source.id)
            } catch {
                failures[source.id] = error
            }
        }
        return failures
    }

    public func renameSource(id: String, to name: String) throws {
        guard let index = state.sources.firstIndex(where: { $0.id == id }) else {
            throw SkillManagerError.sourceNotFound(id)
        }
        state.sources[index].name = name
        try save()
    }

    /// Removes a source, its global links and, for git sources, its clone.
    /// Projects keep their lock entries and pinned snapshots, so they still work and can restore the source.
    public func removeSource(id: String) throws {
        guard let source = source(withID: id) else {
            throw SkillManagerError.sourceNotFound(id)
        }
        let targets = registry.globalTargets(onlyInstalled: false)
        for skill in skills(in: source) {
            for target in targets {
                try installer.uninstall(name: skill.installName, from: target.directory, onlyIfLinkedTo: skill.directory)
            }
            state.tags[skill.id] = nil
            state.disabledSkills.remove(skill.id)
        }
        if source.kind == .git {
            let checkout = directory(for: source)
            if fileManager.fileExists(atPath: checkout.path) {
                try fileManager.removeItem(at: checkout)
            }
        }
        state.sources.removeAll { $0.id == id }
        try save()
        rescan()
    }

    /// Re-reads every source folder.
    public func rescan() {
        skills = state.sources.flatMap { source in
            scanner.scan(source: source, root: directory(for: source))
        }
    }

    public func skill(withID id: String) -> Skill? {
        skills.first { $0.id == id }
    }

    func findSource(location: String) -> SkillSource? {
        let key = Self.normalizedLocation(location)
        return state.sources.first { Self.normalizedLocation($0.location) == key }
    }

    func uniqueSourceID(for name: String) -> String {
        let base = Slug.make(name).isEmpty ? "source" : Slug.make(name)
        var candidate = base
        var counter = 2
        while state.sources.contains(where: { $0.id == candidate }) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    /// `https://github.com/org/skills.git` becomes `skills`.
    public static func repositoryName(from url: String) -> String {
        var trimmed = url.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if trimmed.hasSuffix(".git") { trimmed.removeLast(4) }
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init)
        return last ?? trimmed
    }

    /// Compares locations ignoring case, a trailing slash and a `.git` suffix.
    static func normalizedLocation(_ location: String) -> String {
        var value = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value
    }

    // MARK: - Tags

    public func tags(for skillID: String) -> [String] {
        state.tags[skillID] ?? []
    }

    /// Every tag in use, sorted.
    public var allTags: [String] {
        Array(Set(state.tags.values.flatMap { $0 })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func setTags(_ tags: [String], for skillID: String) throws {
        var seen = Set<String>()
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        state.tags[skillID] = cleaned.isEmpty ? nil : cleaned
        try save()
    }

    public func addTag(_ tag: String, to skillID: String) throws {
        try setTags(tags(for: skillID) + [tag], for: skillID)
    }

    public func removeTag(_ tag: String, from skillID: String) throws {
        try setTags(tags(for: skillID).filter { $0.caseInsensitiveCompare(tag) != .orderedSame }, for: skillID)
    }

    // MARK: - Disabling

    public func isDisabled(_ skill: Skill) -> Bool {
        state.disabledSkills.contains(skill.id)
    }

    /// Disabled skills cannot be enabled globally or added to projects.
    /// Disabling also removes the skill's global links.
    public func setDisabled(_ disabled: Bool, skill: Skill) throws {
        if disabled {
            for target in registry.globalTargets(onlyInstalled: false) {
                try installer.uninstall(name: skill.installName, from: target.directory, onlyIfLinkedTo: skill.directory)
            }
            state.disabledSkills.insert(skill.id)
        } else {
            state.disabledSkills.remove(skill.id)
        }
        try save()
    }

    // MARK: - Global enablement

    /// Skills folders of installed agents, grouped when agents share one.
    public func globalTargets() -> [SkillTarget] {
        registry.globalTargets(onlyInstalled: true)
    }

    public func isEnabled(_ skill: Skill, in target: SkillTarget) -> Bool {
        installer.isLinked(name: skill.installName, in: target.directory, to: skill.directory)
    }

    /// Links a skill into (or removes it from) a global skills folder.
    /// Global skills link to the source checkout, so updating the source updates them.
    public func setEnabled(_ enabled: Bool, skill: Skill, in target: SkillTarget) throws {
        if enabled {
            guard !isDisabled(skill) else { throw SkillManagerError.skillDisabled(skill.name) }
            try installer.install(skill.directory, as: skill.installName, into: target.directory, mode: .symlink)
        } else {
            try installer.uninstall(name: skill.installName, from: target.directory, onlyIfLinkedTo: skill.directory)
        }
    }

    /// Skills enabled in a global folder.
    public func enabledSkills(in target: SkillTarget) -> [Skill] {
        skills.filter { isEnabled($0, in: target) }
    }

    /// Entries in a global skills folder that Squire does not manage.
    public func unmanagedEntries(in target: SkillTarget) -> [String] {
        let managed = Set(enabledSkills(in: target).map(\.installName))
        return installer.entries(in: target.directory).filter { !managed.contains($0) }
    }
}
