import Foundation

public enum InstallerError: Error, LocalizedError, Equatable {
    /// A folder or file Squire did not create is in the way.
    case conflict(path: String)
    case missingSource(path: String)

    public var errorDescription: String? {
        switch self {
        case .conflict(let path):
            return "\(path) already exists and was not installed by Squire."
        case .missingSource(let path):
            return "The skill folder \(path) does not exist."
        }
    }
}

/// What occupies a skill's slot inside a skills folder.
public enum InstalledItem: Equatable, Sendable {
    case missing
    case symlink(destination: URL)
    case directory
    case file
}

/// Places skills into skills folders by symlink or copy, and removes them.
public struct SkillInstaller {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Looks at `directory/name` without following symlinks.
    public func inspect(name: String, in directory: URL) -> InstalledItem {
        let url = directory.appendingPathComponent(name)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return .missing
        }
        switch type {
        case .typeSymbolicLink:
            guard let target = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
                return .symlink(destination: url)
            }
            let resolved = target.hasPrefix("/")
                ? URL(fileURLWithPath: target)
                : directory.appendingPathComponent(target)
            return .symlink(destination: resolved.standardizedFileURL)
        case .typeDirectory:
            return .directory
        default:
            return .file
        }
    }

    /// Whether `directory/name` is a symlink pointing at `target`.
    public func isLinked(name: String, in directory: URL, to target: URL) -> Bool {
        guard case .symlink(let destination) = inspect(name: name, in: directory) else { return false }
        return Self.samePath(destination, target)
    }

    /// Installs `source` as `directory/name`.
    /// - Parameter replaceExisting: Replace a real folder or file already at the destination.
    ///   Existing symlinks are always replaced.
    public func install(
        _ source: URL,
        as name: String,
        into directory: URL,
        mode: InstallMode,
        replaceExisting: Bool = false
    ) throws {
        let resolvedSource = source.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedSource.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw InstallerError.missingSource(path: source.path)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)

        switch inspect(name: name, in: directory) {
        case .missing:
            break
        case .symlink:
            try fileManager.removeItem(at: destination)
        case .directory, .file:
            guard replaceExisting else { throw InstallerError.conflict(path: destination.path) }
            try fileManager.removeItem(at: destination)
        }

        switch mode {
        case .symlink:
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: resolvedSource)
        case .copy:
            try fileManager.copyItem(at: resolvedSource, to: destination)
        }
    }

    /// Removes `directory/name`.
    /// - Parameter onlyIfLinkedTo: When set, only a symlink pointing at this folder is removed.
    @discardableResult
    public func uninstall(name: String, from directory: URL, onlyIfLinkedTo target: URL? = nil) throws -> Bool {
        let item = inspect(name: name, in: directory)
        if item == .missing { return false }
        if let target {
            guard case .symlink(let destination) = item, Self.samePath(destination, target) else {
                return false
            }
        }
        try fileManager.removeItem(at: directory.appendingPathComponent(name))
        return true
    }

    /// Names of every entry in a skills folder, sorted.
    public func entries(in directory: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
