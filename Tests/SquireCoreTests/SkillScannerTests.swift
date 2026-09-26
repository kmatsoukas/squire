import XCTest
@testable import SquireCore

final class SkillScannerTests: XCTestCase {
    func testFindsNestedSkillsAndSkipsIgnoredFolders() throws {
        let temp = try TemporaryDirectory()
        try temp.write("repo/skills/pdf/SKILL.md", skillMarkdown(name: "pdf", description: "PDF tools"))
        try temp.write("repo/skills/pdf/nested/SKILL.md", skillMarkdown(name: "inner", description: "Ignored"))
        try temp.write("repo/other/Docs Writer/SKILL.md", skillMarkdown(name: "Docs Writer", description: "Docs"))
        try temp.write("repo/node_modules/dep/SKILL.md", skillMarkdown(name: "dep", description: "Ignored"))
        try temp.write("repo/.git/hooks/SKILL.md", skillMarkdown(name: "git", description: "Ignored"))
        try temp.write("repo/README.md", "# Repo")

        let source = SkillSource(id: "repo", kind: .local, name: "Repo", location: temp.url.path)
        let skills = SkillScanner().scan(source: source, root: temp.url.appendingPathComponent("repo"))

        XCTAssertEqual(skills.map(\.name), ["Docs Writer", "pdf"])
        let pdf = try XCTUnwrap(skills.first { $0.name == "pdf" })
        XCTAssertEqual(pdf.relativePath, "skills/pdf")
        XCTAssertEqual(pdf.id, "repo/skills/pdf")
        XCTAssertEqual(pdf.description, "PDF tools")
        XCTAssertEqual(skills.first { $0.name == "Docs Writer" }?.installName, "docs-writer")
    }

    func testRootCanBeASkill() throws {
        let temp = try TemporaryDirectory()
        try temp.write("single/SKILL.md", "No frontmatter")
        let source = SkillSource(id: "single", kind: .local, name: "Single", location: temp.url.path)
        let skills = SkillScanner().scan(source: source, root: temp.url.appendingPathComponent("single"))
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills.first?.name, "single")
        XCTAssertEqual(skills.first?.relativePath, "")
        XCTAssertEqual(skills.first?.id, "single")
    }
}
