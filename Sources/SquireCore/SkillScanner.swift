import Foundation

/// Finds skills (folders containing `SKILL.md`) inside a source folder.
public struct SkillScanner {
    /// Folder names never descended into.
    public var ignoredFolders: Set<String> = [".git", "node_modules", ".build", "DerivedData", "__pycache__", ".venv"]
    /// How many folder levels below the root are searched.
    public var maxDepth: Int = 6

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(source: SkillSource, root: URL) -> [Skill] {
        var skills: [Skill] = []
        visit(root.standardizedFileURL, relativePath: "", depth: 0, source: source, into: &skills)
        return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads a single skill folder, or returns `nil` when it has no `SKILL.md`.
    public func readSkill(at directory: URL, sourceID: String, relativePath: String) -> Skill? {
        guard let manifest = manifestURL(in: directory),
              let text = try? String(contentsOf: manifest, encoding: .utf8) else {
            return nil
        }
        let metadata = SkillManifest.parseFrontmatter(text)
        let name = metadata["name"].flatMap { $0.isEmpty ? nil : $0 } ?? directory.lastPathComponent
        return Skill(
            name: name,
            description: metadata["description"] ?? "",
            sourceID: sourceID,
            relativePath: relativePath,
            directory: directory,
            metadata: metadata
        )
    }

    private func visit(_ directory: URL, relativePath: String, depth: Int, source: SkillSource, into skills: inout [Skill]) {
        if let skill = readSkill(at: directory, sourceID: source.id, relativePath: relativePath) {
            skills.append(skill)
            // A skill's own subfolders (scripts, references) are not separate skills.
            return
        }
        guard depth < maxDepth,
              let children = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        for child in children.sorted() {
            if ignoredFolders.contains(child) || (child.hasPrefix(".") && child != ".agents" && child != ".claude") {
                continue
            }
            let url = directory.appendingPathComponent(child)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let childPath = relativePath.isEmpty ? child : "\(relativePath)/\(child)"
            visit(url, relativePath: childPath, depth: depth + 1, source: source, into: &skills)
        }
    }

    private func manifestURL(in directory: URL) -> URL? {
        let exact = directory.appendingPathComponent(SkillManifest.fileName)
        if fileManager.fileExists(atPath: exact.path) { return exact }
        let lower = directory.appendingPathComponent("skill.md")
        if fileManager.fileExists(atPath: lower.path) { return lower }
        return nil
    }
}
