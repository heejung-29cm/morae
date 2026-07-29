import XCTest
@testable import MoraeCore

final class MoraeCoreTests: XCTestCase {
    func testSmokeMessage() {
        XCTAssertEqual(MoraeRuntime.smokeMessage, "morae-cli-ok")
    }

    func testLocalDayUsesProvidedTimeZoneAtDateBoundary() {
        let instant = ISO8601DateFormatter().date(from: "2026-07-29T15:30:00Z")!
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        XCTAssertEqual(LocalDay(date: instant, calendar: seoul).rawValue, "2026-07-30")
        XCTAssertEqual(
            LocalDay(date: instant, calendar: losAngeles).rawValue,
            "2026-07-29"
        )
    }

    func testLocalDayRejectsInvalidCalendarDate() {
        XCTAssertThrowsError(try LocalDay(rawValue: "2026-02-30"))
        XCTAssertThrowsError(try LocalDay(rawValue: "2026-2-03"))
    }

    func testUnixMillisecondsRoundTrip() {
        let milliseconds: Int64 = 1_775_039_400_123
        XCTAssertEqual(Date(unixMilliseconds: milliseconds).unixMilliseconds, milliseconds)
    }

    func testUUIDBackedIDStorageAndCodableRoundTrip() throws {
        let uuid = UUID(uuidString: "8E5BC6BE-5197-4392-A7D9-780D3EB58033")!
        let id = TodoID(rawValue: uuid)

        XCTAssertEqual(id.storageValue, "8e5bc6be-5197-4392-a7d9-780d3eb58033")
        let decoded = try JSONDecoder().decode(
            TodoID.self,
            from: JSONEncoder().encode(id)
        )
        XCTAssertEqual(decoded, id)
    }
}
