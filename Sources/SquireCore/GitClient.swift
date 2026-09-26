import Foundation

/// Thin wrapper around the `git` command line tool.
public struct GitClient: Sendable {
    public var runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    @discardableResult
    func git(_ arguments: [String], in directory: URL? = nil) throws -> String {
        try runner.run("git", arguments, in: directory)
    }

    /// Clones `url` into `destination`, which must not exist yet.
    public func clone(_ url: String, to destination: URL, branch: String? = nil) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var arguments = ["clone", "--quiet"]
        if let branch, !branch.isEmpty {
            arguments += ["--branch", branch]
        }
        arguments += ["--", url, destination.path]
        try git(arguments)
    }

    /// Fetches and fast-forwards the checked-out branch.
    public func pull(_ repository: URL) throws {
        try git(["-C", repository.path, "pull", "--quiet", "--ff-only"])
    }

    /// The commit currently checked out.
    public func headCommit(_ repository: URL) throws -> String {
        try git(["-C", repository.path, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last commit that changed `path` (relative to the repository root), or HEAD when `path` is empty.
    /// Used as a skill's version so it only changes when the skill itself changes.
    public func lastCommit(touching path: String, in repository: URL) throws -> String {
        guard !path.isEmpty else { return try headCommit(repository) }
        let output = try git(["-C", repository.path, "log", "-1", "--format=%H", "--", path])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return try headCommit(repository)
        }
        return output
    }

    /// Whether `commit` exists in the local clone.
    public func hasCommit(_ commit: String, in repository: URL) -> Bool {
        (try? git(["-C", repository.path, "cat-file", "-e", "\(commit)^{commit}"])) != nil
    }

    /// Fetches from the remote so older or newer commits are available locally.
    public func fetch(_ repository: URL) throws {
        try git(["-C", repository.path, "fetch", "--quiet", "--tags", "origin"])
    }

    /// Writes the contents of `path` at `commit` into `destination`.
    public func export(path: String, at commit: String, from repository: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let archive = fileManager.temporaryDirectory.appendingPathComponent("squire-\(UUID().uuidString).tar")
        defer { try? fileManager.removeItem(at: archive) }
        let treeish = path.isEmpty ? commit : "\(commit):\(path)"
        try runner.run(
            "git",
            ["-C", repository.path, "archive", "--format=tar", treeish],
            standardOutput: archive
        )
        try runner.run("tar", ["-xf", archive.path, "-C", destination.path])
    }

    /// The URL of the `origin` remote.
    public func remoteURL(_ repository: URL) throws -> String {
        try git(["-C", repository.path, "remote", "get-url", "origin"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
