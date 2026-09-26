import Foundation

public struct ProcessError: Error, LocalizedError, Sendable {
    public let command: String
    public let status: Int32
    public let output: String

    public var errorDescription: String? {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "\(command) failed with exit code \(status)."
            : "\(command) failed: \(detail)"
    }
}

/// Runs command-line tools and captures their output.
public struct ProcessRunner: Sendable {
    /// Extra folders searched for executables. Apps launched from Finder get a minimal `PATH`.
    public static let extraSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    public init() {}

    /// Runs `executable` with `arguments` and returns its standard output.
    /// - Parameter standardOutput: When set, standard output is written to this file instead of being returned.
    @discardableResult
    public func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL? = nil,
        standardOutput: URL? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let directory {
            process.currentDirectoryURL = directory
        }

        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? ""
        environment["PATH"] = ([path] + Self.extraSearchPaths).filter { !$0.isEmpty }.joined(separator: ":")
        // Never block on a credential prompt.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        // Output goes to temporary files so large output cannot fill a pipe and block the process.
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("squire-\(UUID().uuidString)")
        let outURL = standardOutput ?? scratch.appendingPathExtension("out")
        let errURL = scratch.appendingPathExtension("err")
        fileManager.createFile(atPath: outURL.path, contents: nil)
        fileManager.createFile(atPath: errURL.path, contents: nil)
        defer {
            if standardOutput == nil { try? fileManager.removeItem(at: outURL) }
            try? fileManager.removeItem(at: errURL)
        }
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()

        let output = standardOutput == nil
            ? (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
            : ""
        guard process.terminationStatus == 0 else {
            let errorText = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            throw ProcessError(
                command: ([executable] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                output: errorText.isEmpty ? output : errorText
            )
        }
        return output
    }
}
