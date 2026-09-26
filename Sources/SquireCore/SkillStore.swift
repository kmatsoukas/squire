import Foundation

/// Immutable, versioned copies of skills taken from git sources.
///
/// Projects link to snapshots here, so a project keeps the exact version in its
/// lock file even after the source repository moves on.
/// Layout: `<root>/<source id>/<skill install name>/<commit>`.
public struct SkillStore {
    public let root: URL
    private let git: GitClient
    private let fileManager: FileManager

    public init(root: URL, git: GitClient = GitClient(), fileManager: FileManager = .default) {
        self.root = root
        self.git = git
        self.fileManager = fileManager
    }

    public func snapshotDirectory(sourceID: String, skillName: String, version: String) -> URL {
        root
            .appendingPathComponent(sourceID, isDirectory: true)
            .appendingPathComponent(skillName, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    public func hasSnapshot(sourceID: String, skillName: String, version: String) -> Bool {
        fileManager.fileExists(atPath: snapshotDirectory(sourceID: sourceID, skillName: skillName, version: version).path)
    }

    /// Returns the snapshot folder for `version`, exporting it from `repository` first if needed.
    /// Fetches from the remote when the commit is not in the local clone.
    @discardableResult
    public func snapshot(
        sourceID: String,
        skillName: String,
        relativePath: String,
        version: String,
        repository: URL
    ) throws -> URL {
        let destination = snapshotDirectory(sourceID: sourceID, skillName: skillName, version: version)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }
        if !git.hasCommit(version, in: repository) {
            try git.fetch(repository)
        }
        // Export into a temporary sibling and move it into place, so a failed export never leaves a partial snapshot.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try git.export(path: relativePath, at: version, from: repository, to: staging)
        try fileManager.moveItem(at: staging, to: destination)
        return destination
    }

    /// Deletes every snapshot of a source, for example when the source is removed.
    public func removeSnapshots(sourceID: String) throws {
        let directory = root.appendingPathComponent(sourceID, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }
}
