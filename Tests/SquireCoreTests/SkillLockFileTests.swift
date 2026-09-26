import XCTest
@testable import SquireCore

final class SkillLockFileTests: XCTestCase {
    func testRoundTripIsStable() throws {
        let temp = try TemporaryDirectory()
        let store = LockFileStore()
        var lockFile = SkillLockFile(installMode: .copy, agents: ["claude-code"])
        lockFile.skills["pdf"] = LockedSkill(
            source: "https://github.com/example/skills.git",
            sourceType: .git,
            path: "skills/pdf",
            version: "abc123"
        )
        try store.write(lockFile, project: temp.url)

        XCTAssertEqual(store.url(for: temp.url).path, temp.url.appendingPathComponent(".ai/skills.lock.json").path)
        XCTAssertEqual(try store.read(project: temp.url), lockFile)

        let text = try String(contentsOf: store.url(for: temp.url), encoding: .utf8)
        XCTAssertTrue(text.contains("\"source\" : \"https://github.com/example/skills.git\""))
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testDecodesMinimalFile() throws {
        let json = """
        { "skills": { "notes": { "source": "/Users/me/skills", "path": "notes", "version": "local" } } }
        """
        let lockFile = try JSONDecoder().decode(SkillLockFile.self, from: Data(json.utf8))
        XCTAssertEqual(lockFile.lockfileVersion, 1)
        XCTAssertEqual(lockFile.installMode, .symlink)
        XCTAssertEqual(lockFile.skills["notes"]?.sourceType, .local)
    }

    func testMissingLockFileReadsAsNil() throws {
        let temp = try TemporaryDirectory()
        XCTAssertNil(try LockFileStore(folderName: ".skills").read(project: temp.url))
    }
}
