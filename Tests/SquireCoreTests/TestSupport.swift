import Foundation
import XCTest
@testable import SquireCore

/// A temporary folder removed at the end of the test.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("squire-tests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func folder(_ path: String) throws -> URL {
        let folder = url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @discardableResult
    func write(_ path: String, _ contents: String) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

func skillMarkdown(name: String, description: String) -> String {
    """
    ---
    name: \(name)
    description: \(description)
    ---

    # \(name)
    """
}

/// Runs git with a fixed identity, for building fixture repositories.
@discardableResult
func runGit(_ arguments: [String], in directory: URL) throws -> String {
    try ProcessRunner().run(
        "git",
        ["-c", "user.name=Squire Tests", "-c", "user.email=tests@example.com", "-c", "init.defaultBranch=main", "-c", "commit.gpgsign=false"]
            + arguments,
        in: directory
    )
}

/// Creates a git repository at `directory` and commits everything in it.
func makeRepository(at directory: URL) throws {
    try runGit(["init", "--quiet"], in: directory)
    try commitAll(in: directory, message: "Initial")
}

func commitAll(in directory: URL, message: String) throws {
    try runGit(["add", "-A"], in: directory)
    try runGit(["commit", "--quiet", "-m", message], in: directory)
}
