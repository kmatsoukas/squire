import XCTest
@testable import SquireCore

final class SkillManifestTests: XCTestCase {
    func testParsesSimpleKeys() {
        let text = """
        ---
        name: pdf
        description: "Work with PDF files: read, merge, split"
        license: MIT # comment
        ---
        Body
        """
        let result = SkillManifest.parseFrontmatter(text)
        XCTAssertEqual(result["name"], "pdf")
        XCTAssertEqual(result["description"], "Work with PDF files: read, merge, split")
        XCTAssertEqual(result["license"], "MIT")
    }

    func testParsesBlockValuesAndNestedKeys() {
        let text = """
        ---
        name: writer
        description: >
          Helps write
          long documents.
        notes: |
          line one
          line two
        metadata:
          version: 1.2
          author: 'Jo''s team'
        ---
        """
        let result = SkillManifest.parseFrontmatter(text)
        XCTAssertEqual(result["description"], "Helps write long documents.")
        XCTAssertEqual(result["notes"], "line one\nline two")
        XCTAssertEqual(result["metadata.version"], "1.2")
        XCTAssertEqual(result["metadata.author"], "Jo's team")
    }

    func testMissingOrUnclosedFrontmatter() {
        XCTAssertEqual(SkillManifest.parseFrontmatter("# Just markdown"), [:])
        XCTAssertEqual(SkillManifest.parseFrontmatter("---\nname: x\n"), [:])
    }

    func testCRLFLineEndings() {
        let result = SkillManifest.parseFrontmatter("---\r\nname: crlf\r\n---\r\n")
        XCTAssertEqual(result["name"], "crlf")
    }
}
