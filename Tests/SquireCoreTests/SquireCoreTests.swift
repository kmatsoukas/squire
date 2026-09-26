import XCTest
@testable import SquireCore

final class SquireCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(SquireCore.version.isEmpty)
    }
}
