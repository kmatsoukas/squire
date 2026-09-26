import XCTest
@testable import SquireCore

final class SkillManagerTests: XCTestCase {
    var temp: TemporaryDirectory!
    var home: URL!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        home = try temp.folder("home")
        // Claude Code and pi are "installed".
        _ = try temp.folder("home/.claude")
        _ = try temp.folder("home/.pi")
    }

    func makeManager() throws -> SkillManager {
        try SkillManager(
            paths: SquirePaths(supportDirectory: temp.url.appendingPathComponent("support")),
            pathResolver: PathResolver(home: home)
        )
    }

    func makeGitRepository() throws -> URL {
        let repo = try temp.folder("remote-skills")
        try temp.write("remote-skills/skills/pdf/SKILL.md", skillMarkdown(name: "pdf", description: "PDF v1"))
        try temp.write("remote-skills/skills/notes/SKILL.md", skillMarkdown(name: "notes", description: "Notes"))
        try makeRepository(at: repo)
        return repo
    }

    func testLocalSourceTagsAndPersistence() throws {
        try temp.write("local/review/SKILL.md", skillMarkdown(name: "review", description: "Reviews code"))
        let manager = try makeManager()
        let source = try manager.addLocalSource(path: temp.url.appendingPathComponent("local").path)
        XCTAssertEqual(manager.skills(in: source).map(\.name), ["review"])

        let skill = try XCTUnwrap(manager.skills.first)
        try manager.setTags(["work", " Work ", "", "go"], for: skill.id)
        XCTAssertEqual(manager.tags(for: skill.id), ["work", "go"])
        XCTAssertEqual(manager.allTags, ["go", "work"])

        let reloaded = try makeManager()
        XCTAssertEqual(reloaded.tags(for: skill.id), ["work", "go"])
        XCTAssertEqual(reloaded.skills.map(\.id), [skill.id])
        XCTAssertThrowsError(try reloaded.addLocalSource(path: source.location))
    }

    func testGitSourceCloneAndUpdate() throws {
        let repo = try makeGitRepository()
        let manager = try makeManager()
        let source = try manager.addGitSource(url: repo.path)
        XCTAssertEqual(source.id, "remote-skills")
        XCTAssertEqual(manager.skills(in: source).map(\.name), ["notes", "pdf"])

        try temp.write("remote-skills/skills/lint/SKILL.md", skillMarkdown(name: "lint", description: "Lint"))
        try commitAll(in: repo, message: "Add lint")
        try manager.updateSource(id: source.id)
        XCTAssertEqual(manager.skills(in: source).map(\.name), ["lint", "notes", "pdf"])

        try manager.removeSource(id: source.id)
        XCTAssertTrue(manager.skills.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.directory(for: source).path))
    }

    func testGlobalEnablementAndDisabling() throws {
        try temp.write("local/review/SKILL.md", skillMarkdown(name: "review", description: "Reviews code"))
        let manager = try makeManager()
        try manager.addLocalSource(path: temp.url.appendingPathComponent("local").path)
        let skill = try XCTUnwrap(manager.skills.first)

        let targets = manager.globalTargets()
        XCTAssertEqual(targets.map(\.directory.lastPathComponent), ["skills", "skills"])
        let agentsTarget = try XCTUnwrap(targets.first { $0.directory.path.hasSuffix(".agents/skills") })

        try manager.setEnabled(true, skill: skill, in: agentsTarget)
        XCTAssertTrue(manager.isEnabled(skill, in: agentsTarget))
        XCTAssertEqual(manager.enabledSkills(in: agentsTarget).map(\.id), [skill.id])

        try temp.write("home/.agents/skills/hand-made/SKILL.md", "x")
        XCTAssertEqual(manager.unmanagedEntries(in: agentsTarget), ["hand-made"])

        try manager.setDisabled(true, skill: skill)
        XCTAssertFalse(manager.isEnabled(skill, in: agentsTarget))
        XCTAssertThrowsError(try manager.setEnabled(true, skill: skill, in: agentsTarget))
    }

    func testProjectLockFileInstallAndUpdate() throws {
        let repo = try makeGitRepository()
        let manager = try makeManager()
        try manager.addGitSource(url: repo.path)
        let projectFolder = try temp.folder("project")

        let project = try manager.addProject(path: projectFolder.path)
        XCTAssertTrue(manager.lockStore.exists(in: projectFolder))

        try manager.setAgents(["claude-code", "opencode", "pi"], for: project)
        let pdf = try XCTUnwrap(manager.skills.first { $0.name == "pdf" })
        try manager.addSkill(pdf, to: project)

        var lockFile = try manager.lockFile(for: project)
        let firstVersion = try XCTUnwrap(lockFile.skills["pdf"]?.version)
        XCTAssertEqual(lockFile.skills["pdf"]?.path, "skills/pdf")
        XCTAssertEqual(lockFile.skills["pdf"]?.source, repo.path)

        let claudeLink = projectFolder.appendingPathComponent(".claude/skills/pdf/SKILL.md")
        let agentsLink = projectFolder.appendingPathComponent(".agents/skills/pdf/SKILL.md")
        XCTAssertTrue(try String(contentsOf: claudeLink, encoding: .utf8).contains("PDF v1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsLink.path))
        XCTAssertEqual(try manager.projectStatus(project).map(\.isInstalled), [true])

        // A new commit upstream shows up as an update, and updating moves the pin.
        try temp.write("remote-skills/skills/pdf/SKILL.md", skillMarkdown(name: "pdf", description: "PDF v2"))
        try commitAll(in: repo, message: "Update pdf")
        let status = try manager.checkForUpdates(project)
        XCTAssertEqual(status.first?.hasUpdate, true)
        XCTAssertTrue(try String(contentsOf: claudeLink, encoding: .utf8).contains("PDF v1"), "pinned version stays until updated")

        try manager.updateProjectSkills(project)
        lockFile = try manager.lockFile(for: project)
        XCTAssertNotEqual(lockFile.skills["pdf"]?.version, firstVersion)
        XCTAssertTrue(try String(contentsOf: claudeLink, encoding: .utf8).contains("PDF v2"))
        XCTAssertEqual(try manager.projectStatus(project).first?.hasUpdate, false)

        // Copy mode replaces links with real folders.
        try manager.setInstallMode(.copy, for: project)
        XCTAssertEqual(SkillInstaller().inspect(name: "pdf", in: projectFolder.appendingPathComponent(".claude/skills")), .directory)

        try manager.removeSkill(named: "pdf", from: project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: claudeLink.path))
        XCTAssertTrue(try manager.lockFile(for: project).skills.isEmpty)
    }

    func testSyncRestoresFromLockFileOnAnotherMachine() throws {
        let repo = try makeGitRepository()
        let projectFolder = try temp.folder("project")

        let first = try makeManager()
        try first.addGitSource(url: repo.path)
        let project = try first.addProject(path: projectFolder.path)
        try first.addSkill(try XCTUnwrap(first.skills.first { $0.name == "notes" }), to: project)
        try FileManager.default.removeItem(at: projectFolder.appendingPathComponent(".claude"))

        // A fresh library with no sources restores everything from the lock file.
        let second = try SkillManager(
            paths: SquirePaths(supportDirectory: temp.url.appendingPathComponent("support-2")),
            pathResolver: PathResolver(home: home)
        )
        let restored = try second.addProject(path: projectFolder.path)
        try second.syncProject(restored)
        XCTAssertEqual(second.state.sources.map(\.location), [repo.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent(".claude/skills/notes/SKILL.md").path))
    }

    func testChangingRepositoriesFolderMovesClonesAndRelinks() throws {
        let repo = try makeGitRepository()
        let manager = try makeManager()
        let source = try manager.addGitSource(url: repo.path)
        let oldClone = manager.directory(for: source)
        let pdf = try XCTUnwrap(manager.skills.first { $0.name == "pdf" })
        let target = try XCTUnwrap(manager.globalTargets().first)
        try manager.setEnabled(true, skill: pdf, in: target)

        var settings = manager.state.settings
        settings.repositoriesPath = temp.url.appendingPathComponent("my-repos").path
        try manager.updateSettings(settings)

        let newClone = manager.directory(for: source)
        XCTAssertEqual(newClone.path, temp.url.appendingPathComponent("my-repos/remote-skills").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldClone.path))
        XCTAssertFalse(manager.isCheckoutMissing(source))
        XCTAssertEqual(manager.skills(in: source).map(\.name), ["notes", "pdf"])

        let moved = try XCTUnwrap(manager.skills.first { $0.name == "pdf" })
        XCTAssertTrue(manager.isEnabled(moved, in: target))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.directory.appendingPathComponent("pdf/SKILL.md").path))

        // The setting survives a restart.
        XCTAssertEqual(try makeManager().directory(for: source).path, newClone.path)
    }

    func testMissingCloneIsReportedAndRestoredByUpdate() throws {
        let repo = try makeGitRepository()
        let manager = try makeManager()
        let source = try manager.addGitSource(url: repo.path)
        try FileManager.default.removeItem(at: manager.directory(for: source))
        manager.rescan()

        XCTAssertTrue(manager.isCheckoutMissing(source))
        XCTAssertTrue(manager.skills.isEmpty)
        try manager.updateSource(id: source.id)
        XCTAssertFalse(manager.isCheckoutMissing(source))
        XCTAssertEqual(manager.skills.count, 2)
    }

    func testImportsClonesFoundInRepositoriesFolder() throws {
        let repo = try makeGitRepository()
        let reposFolder = try temp.folder("clones")
        try runGit(["clone", "--quiet", repo.path, reposFolder.appendingPathComponent("team-skills").path], in: temp.url)
        _ = try temp.folder("clones/not-a-repo")

        let manager = try makeManager()
        var settings = manager.state.settings
        settings.repositoriesPath = reposFolder.path
        try manager.updateSettings(settings)

        XCTAssertEqual(manager.state.sources.map(\.id), ["team-skills"])
        XCTAssertEqual(manager.state.sources.first?.location, repo.path)
        XCTAssertEqual(manager.skills.map(\.name), ["notes", "pdf"])
        XCTAssertTrue(try manager.importExistingClones().isEmpty, "already imported")
    }

    func testRepositoryName() {
        XCTAssertEqual(SkillManager.repositoryName(from: "https://github.com/anthropics/skills.git"), "skills")
        XCTAssertEqual(SkillManager.repositoryName(from: "git@github.com:org/agent-skills.git"), "agent-skills")
        XCTAssertEqual(SkillManager.repositoryName(from: "/Users/me/skills/"), "skills")
    }
}
