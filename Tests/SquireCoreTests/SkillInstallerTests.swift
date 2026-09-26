import XCTest
@testable import SquireCore

final class SkillInstallerTests: XCTestCase {
    func testSymlinkInstallAndUninstall() throws {
        let temp = try TemporaryDirectory()
        let skill = try temp.write("source/pdf/SKILL.md", "x").deletingLastPathComponent()
        let target = temp.url.appendingPathComponent("target")
        let installer = SkillInstaller()

        try installer.install(skill, as: "pdf", into: target, mode: .symlink)
        XCTAssertTrue(installer.isLinked(name: "pdf", in: target, to: skill))
        XCTAssertEqual(installer.entries(in: target), ["pdf"])

        let other = try temp.folder("elsewhere")
        XCTAssertFalse(try installer.uninstall(name: "pdf", from: target, onlyIfLinkedTo: other))
        XCTAssertTrue(try installer.uninstall(name: "pdf", from: target, onlyIfLinkedTo: skill))
        XCTAssertEqual(installer.inspect(name: "pdf", in: target), .missing)
    }

    func testCopyInstall() throws {
        let temp = try TemporaryDirectory()
        let skill = try temp.write("source/pdf/SKILL.md", "x").deletingLastPathComponent()
        let target = temp.url.appendingPathComponent("target")
        let installer = SkillInstaller()

        try installer.install(skill, as: "pdf", into: target, mode: .copy)
        XCTAssertEqual(installer.inspect(name: "pdf", in: target), .directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("pdf/SKILL.md").path))
    }

    func testRefusesToReplaceForeignFolderUnlessAsked() throws {
        let temp = try TemporaryDirectory()
        let skill = try temp.write("source/pdf/SKILL.md", "x").deletingLastPathComponent()
        let target = try temp.folder("target")
        try temp.write("target/pdf/SKILL.md", "mine")
        let installer = SkillInstaller()

        XCTAssertThrowsError(try installer.install(skill, as: "pdf", into: target, mode: .symlink)) { error in
            XCTAssertEqual(error as? InstallerError, .conflict(path: target.appendingPathComponent("pdf").path))
        }
        try installer.install(skill, as: "pdf", into: target, mode: .symlink, replaceExisting: true)
        XCTAssertTrue(installer.isLinked(name: "pdf", in: target, to: skill))
    }

    func testReplacesExistingSymlink() throws {
        let temp = try TemporaryDirectory()
        let first = try temp.write("a/pdf/SKILL.md", "a").deletingLastPathComponent()
        let second = try temp.write("b/pdf/SKILL.md", "b").deletingLastPathComponent()
        let target = temp.url.appendingPathComponent("target")
        let installer = SkillInstaller()

        try installer.install(first, as: "pdf", into: target, mode: .symlink)
        try installer.install(second, as: "pdf", into: target, mode: .symlink)
        XCTAssertTrue(installer.isLinked(name: "pdf", in: target, to: second))
    }
}
