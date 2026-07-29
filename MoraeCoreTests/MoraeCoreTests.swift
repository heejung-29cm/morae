import XCTest
@testable import MoraeCore

final class MoraeCoreTests: XCTestCase {
    func testSmokeMessage() {
        XCTAssertEqual(MoraeRuntime.smokeMessage, "morae-cli-ok")
    }
}
