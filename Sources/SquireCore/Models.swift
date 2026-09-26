import Foundation

/// Namespace for the Squire core library.
public enum SquireCore {
    public static let version = "0.1.0"
}

/// Where skills come from: a git repository Squire clones, or a folder on disk.
public struct SkillSource: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case git
        case local
    }

    /// Stable, filesystem-safe identifier, also used as the clone folder name.
    public var id: String
    public var kind: Kind
    public var name: String
    /// A git URL for `.git` sources, an absolute path for `.local` sources.
    public var location: String
    /// Branch to clone and pull. `nil` uses the remote's default branch.
    public var branch: String?
    /// Commit checked out after the last clone or pull (git sources only).
    public var revision: String?
    public var lastUpdated: Date?

    public init(
        id: String,
        kind: Kind,
        name: String,
        location: String,
        branch: String? = nil,
        revision: String? = nil,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.location = location
        self.branch = branch
        self.revision = revision
        self.lastUpdated = lastUpdated
    }
}

/// A skill found in a source: a folder containing a `SKILL.md` file.
public struct Skill: Identifiable, Hashable, Sendable {
    /// `<source id>/<relative path>`, unique across the library.
    public let id: String
    /// Name from the `SKILL.md` frontmatter, falling back to the folder name.
    public let name: String
    public let description: String
    public let sourceID: String
    /// Path of the skill folder relative to the source root. Empty when the source root is the skill.
    public let relativePath: String
    /// Absolute location of the skill folder in the source checkout.
    public let directory: URL
    /// Every frontmatter key, including `name` and `description`.
    public let metadata: [String: String]

    public init(
        name: String,
        description: String,
        sourceID: String,
        relativePath: String,
        directory: URL,
        metadata: [String: String] = [:]
    ) {
        self.id = Skill.makeID(sourceID: sourceID, relativePath: relativePath)
        self.name = name
        self.description = description
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.directory = directory
        self.metadata = metadata
    }

    public static func makeID(sourceID: String, relativePath: String) -> String {
        relativePath.isEmpty ? sourceID : "\(sourceID)/\(relativePath)"
    }

    /// Folder name used when the skill is installed into an agent's skills folder.
    public var installName: String {
        Slug.make(name).isEmpty ? directory.lastPathComponent : Slug.make(name)
    }
}

/// How a skill is placed into a skills folder.
public enum InstallMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A symbolic link to the source checkout or the versioned store.
    case symlink
    /// A full copy of the skill folder.
    case copy

    public var id: String { rawValue }
}

/// A folder Squire manages skills for.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String

    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// User preferences stored with the library.
public struct SquireSettings: Codable, Hashable, Sendable {
    /// Folder inside each project that holds the lock file.
    public var projectFolderName: String
    public var lockFileName: String
    public var defaultInstallMode: InstallMode
    /// Agents selected for newly added projects.
    public var defaultProjectAgents: [String]

    public init(
        projectFolderName: String = ".ai",
        lockFileName: String = "skills.lock.json",
        defaultInstallMode: InstallMode = .symlink,
        defaultProjectAgents: [String] = ["claude-code"]
    ) {
        self.projectFolderName = projectFolderName
        self.lockFileName = lockFileName
        self.defaultInstallMode = defaultInstallMode
        self.defaultProjectAgents = defaultProjectAgents
    }

    public init(from decoder: Decoder) throws {
        let defaults = SquireSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectFolderName = try container.decodeIfPresent(String.self, forKey: .projectFolderName) ?? defaults.projectFolderName
        lockFileName = try container.decodeIfPresent(String.self, forKey: .lockFileName) ?? defaults.lockFileName
        defaultInstallMode = try container.decodeIfPresent(InstallMode.self, forKey: .defaultInstallMode) ?? defaults.defaultInstallMode
        defaultProjectAgents = try container.decodeIfPresent([String].self, forKey: .defaultProjectAgents) ?? defaults.defaultProjectAgents
    }
}

/// Everything Squire persists in `library.json`.
public struct LibraryState: Codable, Hashable, Sendable {
    public var sources: [SkillSource]
    /// Skill id to tags.
    public var tags: [String: [String]]
    /// Skill ids hidden from installation.
    public var disabledSkills: Set<String>
    public var projects: [Project]
    /// Agents added by the user on top of the built-in ones.
    public var customAgents: [AgentDefinition]
    public var settings: SquireSettings

    public init(
        sources: [SkillSource] = [],
        tags: [String: [String]] = [:],
        disabledSkills: Set<String> = [],
        projects: [Project] = [],
        customAgents: [AgentDefinition] = [],
        settings: SquireSettings = SquireSettings()
    ) {
        self.sources = sources
        self.tags = tags
        self.disabledSkills = disabledSkills
        self.projects = projects
        self.customAgents = customAgents
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decodeIfPresent([SkillSource].self, forKey: .sources) ?? []
        tags = try container.decodeIfPresent([String: [String]].self, forKey: .tags) ?? [:]
        disabledSkills = try container.decodeIfPresent(Set<String>.self, forKey: .disabledSkills) ?? []
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        customAgents = try container.decodeIfPresent([AgentDefinition].self, forKey: .customAgents) ?? []
        settings = try container.decodeIfPresent(SquireSettings.self, forKey: .settings) ?? SquireSettings()
    }
}

/// Turns arbitrary names into lowercase, dash-separated identifiers.
public enum Slug {
    public static func make(_ text: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if scalar == "." || scalar == "_" {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }
}
