import Foundation

/// A coding agent that loads skills from a folder.
public struct AgentDefinition: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Global skills folder, `~` expands to the home folder. Example: `~/.claude/skills`.
    public var globalSkillsPath: String
    /// Skills folder relative to a project root. Example: `.claude/skills`.
    public var projectSkillsPath: String
    /// Paths whose existence means the agent is installed. Example: `~/.claude`.
    public var detectionPaths: [String]
    /// Executable names looked up on the search path to detect the agent.
    public var executables: [String]

    public init(
        id: String,
        name: String,
        globalSkillsPath: String,
        projectSkillsPath: String,
        detectionPaths: [String] = [],
        executables: [String] = []
    ) {
        self.id = id
        self.name = name
        self.globalSkillsPath = globalSkillsPath
        self.projectSkillsPath = projectSkillsPath
        self.detectionPaths = detectionPaths
        self.executables = executables
    }
}
