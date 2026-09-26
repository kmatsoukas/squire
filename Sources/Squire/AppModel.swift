import AppKit
import Foundation
import Observation
import SquireCore

/// UI state for the whole app. Wraps `SkillManager` and runs its work off the main thread,
/// one operation at a time.
@MainActor
@Observable
final class AppModel {
    private(set) var manager: SkillManager?

    private(set) var skills: [Skill] = []
    private(set) var sources: [SkillSource] = []
    private(set) var projects: [Project] = []
    private(set) var tags: [String: [String]] = [:]
    private(set) var allTags: [String] = []
    private(set) var disabledSkills: Set<String> = []
    private(set) var settings = SquireSettings()
    /// Global skills folders of installed agents.
    private(set) var targets: [SkillTarget] = []
    /// Every known agent, installed or not.
    private(set) var agents: [AgentDefinition] = []
    private(set) var installedAgentIDs: Set<String> = []

    /// What is running right now, shown in the status banner.
    private(set) var activity: String?
    var errorMessage: String?
    /// Bumped after every operation so views that read the filesystem reload.
    private(set) var revision = 0

    @ObservationIgnored private var pending: Task<Void, Never>?

    init() {
        do {
            manager = try SkillManager()
            refresh()
        } catch {
            errorMessage = "Squire could not load its library: \(error.localizedDescription)"
        }
    }

    func refresh() {
        guard let manager else { return }
        skills = manager.skills
        sources = manager.state.sources
        projects = manager.state.projects
        tags = manager.state.tags
        allTags = manager.allTags
        disabledSkills = manager.state.disabledSkills
        settings = manager.state.settings
        let registry = manager.registry
        agents = registry.agents
        installedAgentIDs = Set(registry.installedAgents().map(\.id))
        targets = registry.globalTargets(onlyInstalled: true)
        revision += 1
    }

    // MARK: - Running work

    /// Queues `work` behind any running operation and runs it off the main thread.
    func run(
        _ title: String,
        _ work: @escaping @Sendable (SkillManager) throws -> Void,
        then completion: (@MainActor () -> Void)? = nil
    ) {
        guard let manager else { return }
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            self?.activity = title
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    try work(manager)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard let self else { return }
            self.activity = nil
            if let failure {
                self.errorMessage = failure
            }
            self.refresh()
            completion?()
        }
    }

    /// Queues a read behind any running operation and returns its result.
    func fetch<T: Sendable>(_ work: @escaping @Sendable (SkillManager) throws -> T) async -> T? {
        guard let manager else { return nil }
        let previous = pending
        let task = Task { () -> T? in
            await previous?.value
            return await Task.detached(priority: .userInitiated) { () -> T? in
                try? work(manager)
            }.value
        }
        pending = Task { _ = await task.value }
        return await task.value
    }

    // MARK: - Sources

    func addGitSource(url: String, branch: String, name: String) {
        run("Cloning \(url)…") { manager in
            try manager.addGitSource(url: url, branch: branch, name: name)
        }
    }

    func addLocalSource(_ folder: URL) {
        let path = folder.path
        run("Adding \(folder.lastPathComponent)…") { manager in
            try manager.addLocalSource(path: path)
        }
    }

    func updateSource(_ source: SkillSource) {
        let id = source.id
        run("Updating \(source.name)…") { manager in
            try manager.updateSource(id: id)
        }
    }

    func updateAllSources() {
        run("Updating all sources…") { manager in
            let failures = manager.updateAllSources()
            if let first = failures.first {
                throw first.value
            }
        }
    }

    func removeSource(_ source: SkillSource) {
        let id = source.id
        run("Removing \(source.name)…") { manager in
            try manager.removeSource(id: id)
        }
    }

    func skillCount(for source: SkillSource) -> Int {
        skills.filter { $0.sourceID == source.id }.count
    }

    func source(for skill: Skill) -> SkillSource? {
        sources.first { $0.id == skill.sourceID }
    }

    // MARK: - Skills

    func tags(for skill: Skill) -> [String] {
        tags[skill.id] ?? []
    }

    func isDisabled(_ skill: Skill) -> Bool {
        disabledSkills.contains(skill.id)
    }

    func addTag(_ tag: String, to skill: Skill) {
        let id = skill.id
        run("Tagging \(skill.name)…") { manager in
            try manager.addTag(tag, to: id)
        }
    }

    func removeTag(_ tag: String, from skill: Skill) {
        let id = skill.id
        run("Tagging \(skill.name)…") { manager in
            try manager.removeTag(tag, from: id)
        }
    }

    func setDisabled(_ disabled: Bool, skill: Skill) {
        run(disabled ? "Disabling \(skill.name)…" : "Enabling \(skill.name)…") { manager in
            try manager.setDisabled(disabled, skill: skill)
        }
    }

    func isEnabled(_ skill: Skill, in target: SkillTarget) -> Bool {
        manager?.isEnabled(skill, in: target) ?? false
    }

    func setEnabled(_ enabled: Bool, skill: Skill, in target: SkillTarget) {
        run(enabled ? "Enabling \(skill.name)…" : "Disabling \(skill.name)…") { manager in
            try manager.setEnabled(enabled, skill: skill, in: target)
        }
    }

    func unmanagedEntries(in target: SkillTarget) -> [String] {
        manager?.unmanagedEntries(in: target) ?? []
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Projects

    func addProject(_ folder: URL) {
        let path = folder.path
        run("Adding \(folder.lastPathComponent)…") { manager in
            try manager.addProject(path: path)
        }
    }

    func removeProject(_ project: Project) {
        let id = project.id
        run("Removing \(project.name)…") { manager in
            try manager.removeProject(id: id)
        }
    }

    func projectDetails(_ project: Project) async -> ProjectDetails? {
        await fetch { manager in
            let lockFile = try manager.lockFile(for: project)
            let statuses = try manager.projectStatus(project)
            return ProjectDetails(
                lockFile: lockFile,
                lockFileURL: manager.lockStore.url(for: project.url),
                statuses: statuses,
                targets: manager.projectTargets(for: project, lockFile: lockFile)
            )
        }
    }

    func addSkills(_ skills: [Skill], to project: Project) {
        run("Adding skills to \(project.name)…") { manager in
            for skill in skills {
                try manager.addSkill(skill, to: project)
            }
        }
    }

    func removeSkill(named name: String, from project: Project) {
        run("Removing \(name)…") { manager in
            try manager.removeSkill(named: name, from: project)
        }
    }

    func syncProject(_ project: Project) {
        run("Installing skills in \(project.name)…") { manager in
            try manager.syncProject(project)
        }
    }

    func checkForUpdates(_ project: Project) {
        run("Checking \(project.name) for updates…") { manager in
            _ = try manager.checkForUpdates(project)
        }
    }

    func updateProjectSkills(_ project: Project, names: [String]? = nil) {
        run("Updating skills in \(project.name)…") { manager in
            try manager.updateProjectSkills(project, names: names)
        }
    }

    func setAgents(_ agentIDs: [String], for project: Project) {
        run("Updating agents for \(project.name)…") { manager in
            try manager.setAgents(agentIDs, for: project)
        }
    }

    func setInstallMode(_ mode: InstallMode, for project: Project) {
        run("Switching \(project.name) to \(mode.rawValue)…") { manager in
            try manager.setInstallMode(mode, for: project)
        }
    }

    // MARK: - Settings

    func updateSettings(_ settings: SquireSettings) {
        run("Saving settings…") { manager in
            try manager.updateSettings(settings)
        }
    }
}

/// A project's lock file and install state, loaded for the project view.
struct ProjectDetails: Sendable {
    var lockFile: SkillLockFile
    var lockFileURL: URL
    var statuses: [ProjectSkillStatus]
    var targets: [SkillTarget]
}
