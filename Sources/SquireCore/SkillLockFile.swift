import Foundation

/// A project's skills manifest, like an npm lock file, stored at `.ai/skills.lock.json`.
public struct SkillLockFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var lockfileVersion: Int
    public var installMode: InstallMode
    /// Agent ids whose project skills folders receive the skills.
    public var agents: [String]
    /// Install name to locked skill.
    public var skills: [String: LockedSkill]

    public init(
        installMode: InstallMode = .symlink,
        agents: [String] = [],
        skills: [String: LockedSkill] = [:]
    ) {
        self.lockfileVersion = Self.currentVersion
        self.installMode = installMode
        self.agents = agents
        self.skills = skills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lockfileVersion = try container.decodeIfPresent(Int.self, forKey: .lockfileVersion) ?? Self.currentVersion
        installMode = try container.decodeIfPresent(InstallMode.self, forKey: .installMode) ?? .symlink
        agents = try container.decodeIfPresent([String].self, forKey: .agents) ?? []
        skills = try container.decodeIfPresent([String: LockedSkill].self, forKey: .skills) ?? [:]
    }
}

/// One skill pinned by a project.
public struct LockedSkill: Codable, Hashable, Sendable {
    /// Git URL or local folder path of the source.
    public var source: String
    public var sourceType: SkillSource.Kind
    /// Skill folder relative to the source root.
    public var path: String
    /// Git commit, or `local` for local folders.
    public var version: String

    public static let localVersion = "local"

    public init(source: String, sourceType: SkillSource.Kind, path: String, version: String) {
        self.source = source
        self.sourceType = sourceType
        self.path = path
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? Self.localVersion
        sourceType = try container.decodeIfPresent(SkillSource.Kind.self, forKey: .sourceType)
            ?? (version == Self.localVersion ? .local : .git)
    }
}

/// Reads and writes lock files inside project folders.
public struct LockFileStore {
    public var folderName: String
    public var fileName: String
    private let fileManager: FileManager

    public init(folderName: String = ".ai", fileName: String = "skills.lock.json", fileManager: FileManager = .default) {
        self.folderName = folderName
        self.fileName = fileName
        self.fileManager = fileManager
    }

    public init(settings: SquireSettings, fileManager: FileManager = .default) {
        self.init(folderName: settings.projectFolderName, fileName: settings.lockFileName, fileManager: fileManager)
    }

    public func url(for project: URL) -> URL {
        project
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    public func exists(in project: URL) -> Bool {
        fileManager.fileExists(atPath: url(for: project).path)
    }

    /// The project's lock file, or `nil` when it has none.
    public func read(project: URL) throws -> SkillLockFile? {
        let fileURL = url(for: project)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(SkillLockFile.self, from: data)
    }

    public func write(_ lockFile: SkillLockFile, project: URL) throws {
        let fileURL = url(for: project)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(lockFile).write(to: fileURL, options: .atomic)
    }

    /// Stable, diff-friendly JSON: sorted keys, two-space indentation, trailing newline.
    public static func encode(_ lockFile: SkillLockFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(lockFile)
        data.append(0x0A)
        return data
    }
}
