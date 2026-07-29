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

    func testStatusRawValuesMatchPersistenceContract() {
        XCTAssertEqual(TodoStatus.completed.rawValue, "completed")
        XCTAssertEqual(TodoPriority.important.rawValue, 1)
        XCTAssertEqual(BriefingStatus.succeeded.rawValue, "succeeded")
        XCTAssertEqual(AgentSource.claude.rawValue, "claude")
        XCTAssertEqual(AgentStatus.attentionRequired.rawValue, "attention_required")
        XCTAssertEqual(AgentClosureReason.terminalEvent.rawValue, "terminal_event")
        XCTAssertEqual(BriefingErrorCode.noEnabledFeeds.rawValue, "no_enabled_feeds")
        XCTAssertEqual(
            AgentIngressErrorCode.unsupportedTransport.rawValue,
            "unsupported_transport"
        )
    }

    func testStatusesCodableRoundTrip() throws {
        try assertCodableRoundTrip(TodoStatus.allCases)
        try assertCodableRoundTrip(TodoPriority.allCases)
        try assertCodableRoundTrip(BriefingStatus.allCases)
        try assertCodableRoundTrip(AgentSource.allCases)
        try assertCodableRoundTrip(AgentStatus.allCases)
        try assertCodableRoundTrip(AgentClosureReason.allCases)
        try assertCodableRoundTrip(BriefingErrorCode.allCases)
        try assertCodableRoundTrip(AgentIngressErrorCode.allCases)
    }

    func testAgentStatusRankPreventsTerminalStateDowngrade() {
        XCTAssertGreaterThan(AgentStatus.failed.rank, AgentStatus.completed.rank)
        XCTAssertGreaterThan(AgentStatus.completed.rank, AgentStatus.responded.rank)
        XCTAssertGreaterThan(
            AgentStatus.responded.rank,
            AgentStatus.attentionRequired.rank
        )
        XCTAssertGreaterThan(AgentStatus.attentionRequired.rank, AgentStatus.running.rank)
        XCTAssertGreaterThan(AgentStatus.running.rank, AgentStatus.cancelled.rank)
    }

    func testAppErrorCodableRoundTripAndLocalizedGuidance() throws {
        let error = AppError(
            code: "database_open_failed",
            userMessage: "Morae could not open its local database.",
            recovery: "Check disk availability, then reopen Morae."
        )
        let decoded = try JSONDecoder().decode(
            AppError.self,
            from: JSONEncoder().encode(error)
        )

        XCTAssertEqual(decoded, error)
        XCTAssertEqual(error.errorDescription, error.userMessage)
        XCTAssertEqual(error.recoverySuggestion, error.recovery)
    }

    private func assertCodableRoundTrip<Value>(
        _ values: [Value]
    ) throws where Value: Codable & Equatable {
        let data = try JSONEncoder().encode(values)
        XCTAssertEqual(try JSONDecoder().decode([Value].self, from: data), values)
    }
}
