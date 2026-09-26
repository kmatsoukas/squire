import XCTest
@testable import SquireCore

final class AgentRegistryTests: XCTestCase {
    func testGroupsAgentsSharingAFolder() {
        let home = URL(fileURLWithPath: "/Users/test")
        let registry = AgentRegistry(paths: PathResolver(home: home), searchPaths: [])
        let targets = registry.globalTargets(onlyInstalled: false)
        let shared = targets.first { $0.directory.path == "/Users/test/.agents/skills" }
        XCTAssertEqual(shared?.agents.map(\.id), ["opencode", "pi"])
        XCTAssertEqual(Set(targets.map(\.directory.path)).count, targets.count)
    }

    func testDetectsInstalledAgentsFromFolders() throws {
        let temp = try TemporaryDirectory()
        _ = try temp.folder(".claude")
        _ = try temp.folder(".pi")
        let registry = AgentRegistry(paths: PathResolver(home: temp.url), searchPaths: [])
        XCTAssertEqual(registry.installedAgents().map(\.id), ["claude-code", "pi"])
        XCTAssertEqual(registry.globalTargets().map(\.displayName), ["Claude Code", "pi"])
    }

    func testDetectsAgentsFromExecutables() throws {
        let temp = try TemporaryDirectory()
        let bin = try temp.folder("bin")
        let executable = try temp.write("bin/opencode", "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let registry = AgentRegistry(paths: PathResolver(home: temp.url), searchPaths: [bin.path])
        XCTAssertEqual(registry.installedAgents().map(\.id), ["opencode"])
    }

    func testProjectTargetsAreDeduplicated() {
        let registry = AgentRegistry(paths: PathResolver(home: URL(fileURLWithPath: "/h")), searchPaths: [])
        let targets = registry.projectTargets(for: ["opencode", "pi", "claude-code", "unknown"], in: URL(fileURLWithPath: "/p"))
        XCTAssertEqual(targets.map(\.directory.path), ["/p/.agents/skills", "/p/.claude/skills"])
    }

    func testCustomAgentReplacesBuiltIn() {
        let custom = AgentDefinition(id: "codex", name: "Codex", globalSkillsPath: "~/.agents/skills", projectSkillsPath: ".agents/skills")
        let registry = AgentRegistry.merging(custom: [custom], paths: PathResolver(home: URL(fileURLWithPath: "/h")))
        XCTAssertEqual(registry.agent(withID: "codex")?.globalSkillsPath, "~/.agents/skills")
        XCTAssertEqual(registry.agents.filter { $0.id == "codex" }.count, 1)
    }
}
