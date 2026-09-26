import Foundation

/// Expands `~` paths against a home folder, which tests can replace.
public struct PathResolver: Sendable {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func expand(_ path: String) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

/// Agents Squire knows about out of the box.
public enum AgentCatalog {
    public static let builtIn: [AgentDefinition] = [
        AgentDefinition(
            id: "claude-code",
            name: "Claude Code",
            globalSkillsPath: "~/.claude/skills",
            projectSkillsPath: ".claude/skills",
            detectionPaths: ["~/.claude"],
            executables: ["claude"]
        ),
        AgentDefinition(
            id: "codex",
            name: "Codex",
            globalSkillsPath: "~/.codex/skills",
            projectSkillsPath: ".codex/skills",
            detectionPaths: ["~/.codex"],
            executables: ["codex"]
        ),
        AgentDefinition(
            id: "opencode",
            name: "opencode",
            globalSkillsPath: "~/.agents/skills",
            projectSkillsPath: ".agents/skills",
            detectionPaths: ["~/.config/opencode", "~/.opencode"],
            executables: ["opencode"]
        ),
        AgentDefinition(
            id: "pi",
            name: "pi",
            globalSkillsPath: "~/.agents/skills",
            projectSkillsPath: ".agents/skills",
            detectionPaths: ["~/.pi"],
            executables: ["pi"]
        ),
        AgentDefinition(
            id: "gemini-cli",
            name: "Gemini CLI",
            globalSkillsPath: "~/.gemini/skills",
            projectSkillsPath: ".gemini/skills",
            detectionPaths: ["~/.gemini"],
            executables: ["gemini"]
        ),
        AgentDefinition(
            id: "cursor",
            name: "Cursor",
            globalSkillsPath: "~/.cursor/skills",
            projectSkillsPath: ".cursor/skills",
            detectionPaths: ["~/.cursor", "/Applications/Cursor.app"],
            executables: ["cursor-agent"]
        ),
        AgentDefinition(
            id: "copilot",
            name: "GitHub Copilot",
            globalSkillsPath: "~/.copilot/skills",
            projectSkillsPath: ".github/skills",
            detectionPaths: ["~/.copilot"],
            executables: ["copilot"]
        )
    ]
}

/// A skills folder and every agent that reads it. Agents sharing a folder,
/// such as opencode and pi with `~/.agents/skills`, form a single target.
public struct SkillTarget: Identifiable, Hashable, Sendable {
    public var id: String { directory.path }
    public let directory: URL
    public let agents: [AgentDefinition]

    public init(directory: URL, agents: [AgentDefinition]) {
        self.directory = directory
        self.agents = agents
    }

    public var displayName: String {
        agents.map(\.name).joined(separator: ", ")
    }
}

/// Knows which agents exist, which are installed, and where their skills live.
public struct AgentRegistry: Sendable {
    public var agents: [AgentDefinition]
    public var paths: PathResolver
    /// Folders searched for agent executables, in addition to `PATH`.
    public var searchPaths: [String]

    public init(
        agents: [AgentDefinition] = AgentCatalog.builtIn,
        paths: PathResolver = PathResolver(),
        searchPaths: [String]? = nil
    ) {
        self.agents = agents
        self.paths = paths
        if let searchPaths {
            self.searchPaths = searchPaths
        } else {
            let environmentPath = ProcessInfo.processInfo.environment["PATH"]?
                .split(separator: ":").map(String.init) ?? []
            let home = paths.home.path
            self.searchPaths = environmentPath + ProcessRunner.extraSearchPaths + [
                "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.npm-global/bin",
                "\(home)/.volta/bin", "\(home)/.opencode/bin", "\(home)/.claude/local"
            ]
        }
    }

    /// Built-in agents plus custom ones; a custom agent with a built-in id replaces it.
    public static func merging(custom: [AgentDefinition], paths: PathResolver = PathResolver()) -> AgentRegistry {
        var merged = AgentCatalog.builtIn.filter { agent in !custom.contains { $0.id == agent.id } }
        merged += custom
        return AgentRegistry(agents: merged, paths: paths)
    }

    public func agent(withID id: String) -> AgentDefinition? {
        agents.first { $0.id == id }
    }

    public func isInstalled(_ agent: AgentDefinition) -> Bool {
        let fileManager = FileManager.default
        for path in agent.detectionPaths where fileManager.fileExists(atPath: paths.expand(path).path) {
            return true
        }
        for executable in agent.executables {
            for folder in searchPaths {
                let candidate = URL(fileURLWithPath: folder).appendingPathComponent(executable).path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return true
                }
            }
        }
        return false
    }

    public func installedAgents() -> [AgentDefinition] {
        agents.filter(isInstalled)
    }

    public func globalSkillsDirectory(for agent: AgentDefinition) -> URL {
        paths.expand(agent.globalSkillsPath)
    }

    /// Global skills folders, one per distinct folder, in agent order.
    public func globalTargets(onlyInstalled: Bool = true) -> [SkillTarget] {
        let candidates = onlyInstalled ? installedAgents() : agents
        return group(candidates) { globalSkillsDirectory(for: $0) }
    }

    /// Project skills folders for the given agents, one per distinct folder.
    public func projectTargets(for agentIDs: [String], in project: URL) -> [SkillTarget] {
        let selected = agentIDs.compactMap(agent(withID:))
        return group(selected) { agent in
            project.appendingPathComponent(agent.projectSkillsPath, isDirectory: true).standardizedFileURL
        }
    }

    private func group(_ agents: [AgentDefinition], directory: (AgentDefinition) -> URL) -> [SkillTarget] {
        var order: [String] = []
        var byPath: [String: (URL, [AgentDefinition])] = [:]
        for agent in agents {
            let url = directory(agent)
            let key = url.path
            if byPath[key] == nil {
                order.append(key)
                byPath[key] = (url, [])
            }
            byPath[key]?.1.append(agent)
        }
        return order.compactMap { key in
            byPath[key].map { SkillTarget(directory: $0.0, agents: $0.1) }
        }
    }
}
