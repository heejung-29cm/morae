import MoraeCore
import XCTest

final class HamsterEventCLITests: XCTestCase {
    func testParsesCodexArgumentWithoutReadingStandardInput() throws {
        var didReadStandardInput = false
        let payload = #"{"type":"agent-turn-complete"}"#

        let invocation = try HamsterEventInvocationParser().parse(
            arguments: [payload],
            readStandardInput: {
                didReadStandardInput = true
                return Data()
            }
        )

        XCTAssertEqual(invocation.source, .codex)
        XCTAssertEqual(invocation.eventHint, "agent-turn-complete")
        XCTAssertEqual(invocation.rawPayload, Data(payload.utf8))
        XCTAssertFalse(didReadStandardInput)
    }

    func testMapsEveryClaudeSubcommandToEventHint() throws {
        let mappings = [
            "claude-turn-start": "UserPromptSubmit",
            "claude-notification": "Notification",
            "claude-task-completed": "TaskCompleted",
            "claude-stop": "Stop",
            "claude-stop-failure": "StopFailure",
        ]

        for (subcommand, expectedHint) in mappings {
            let invocation = try HamsterEventInvocationParser().parse(
                arguments: [subcommand],
                readStandardInput: {
                    Data(#"{"session_id":"session"}"#.utf8)
                }
            )
            XCTAssertEqual(invocation.source, .claude)
            XCTAssertEqual(invocation.eventHint, expectedHint)
        }
    }

    func testRejectsInvalidArgumentsAndNonObjectJSON() {
        let parser = HamsterEventInvocationParser()

        XCTAssertThrowsError(
            try parser.parse(arguments: [], readStandardInput: { Data() })
        )
        XCTAssertThrowsError(
            try parser.parse(
                arguments: ["{}", "{}"],
                readStandardInput: { Data() }
            )
        )
        XCTAssertThrowsError(
            try parser.parse(
                arguments: ["not-json"],
                readStandardInput: { Data() }
            )
        )
        XCTAssertThrowsError(
            try parser.parse(
                arguments: ["claude-stop"],
                readStandardInput: { Data("[]".utf8) }
            )
        )
    }

    func testRawPayloadBoundaryIsAppliedBeforeEnvelopeEncoding() throws {
        let maximum = AgentIPCContract.maximumRawPayloadByteCount
        let validPayload = jsonPayload(byteCount: maximum)
        let oversizedPayload = jsonPayload(byteCount: maximum + 1)
        let parser = HamsterEventInvocationParser()

        XCTAssertNoThrow(
            try parser.parse(
                arguments: ["claude-stop"],
                readStandardInput: { validPayload }
            )
        )
        XCTAssertThrowsError(
            try parser.parse(
                arguments: ["claude-stop"],
                readStandardInput: { oversizedPayload }
            )
        ) { error in
            XCTAssertEqual(
                error as? HamsterEventInvocationError,
                .payloadTooLarge
            )
        }
    }

    private func jsonPayload(byteCount: Int) -> Data {
        let prefix = #"{"value":""#
        let suffix = #""}"#
        let contentCount = byteCount - prefix.utf8.count - suffix.utf8.count
        return Data((prefix + String(repeating: "a", count: contentCount)
            + suffix).utf8)
    }
}
