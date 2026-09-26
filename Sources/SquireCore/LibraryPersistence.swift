import Foundation

/// Folders and files Squire keeps its own data in.
public struct SquirePaths: Sendable {
    public var supportDirectory: URL

    public init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    /// `~/Library/Application Support/Squire` on macOS.
    public static func standard(fileManager: FileManager = .default) -> SquirePaths {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return SquirePaths(supportDirectory: base.appendingPathComponent("Squire", isDirectory: true))
    }

    public var libraryFile: URL { supportDirectory.appendingPathComponent("library.json") }
    public var reposDirectory: URL { supportDirectory.appendingPathComponent("repos", isDirectory: true) }
    public var storeDirectory: URL { supportDirectory.appendingPathComponent("store", isDirectory: true) }
}

/// Loads and saves `library.json`.
public struct LibraryPersistence {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    /// The saved library, or an empty one when nothing has been saved yet.
    public func load() throws -> LibraryState {
        guard fileManager.fileExists(atPath: fileURL.path) else { return LibraryState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryState.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ state: LibraryState) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
