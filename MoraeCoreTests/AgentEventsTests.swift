import Foundation
@testable import MoraeCore
import XCTest

final class AgentEventsTests: XCTestCase {
    private let date = Date(unixMilliseconds: 1_800_000_000_000)

    func testCodexNormalizerPreservesIdentifiersAndDefaultsToPrivacyOff() throws {
        let data = Data(#"{"type":"agent-turn-complete","thread-id":"thread","turn-id":"turn","cwd":"/private/project","input-messages":["secret prompt"],"last-assistant-message":"secret result"}"#.utf8)
        let event = try AgentEventNormalizer.codex(
            JSONDecoder().decode(CodexNotifyDTO.self, from: data),
            receivedAt: date,
            privacy: AgentPrivacyPolicy()
        )

        XCTAssertEqual(event.sessionID, "thread")
        XCTAssertEqual(event.turnID, "turn")
        XCTAssertEqual(event.status, .responded)
        XCTAssertTrue(event.closesRun)
        XCTAssertNil(event.projectPath)
        XCTAssertNil(event.title)
        XCTAssertNil(event.lastMessage)
    }

    func testCodexRejectsUnsupportedEvent() throws {
        let data = Data(#"{"type":"turn-start","thread-id":"thread","turn-id":"turn"}"#.utf8)
        let dto = try JSONDecoder().decode(CodexNotifyDTO.self, from: data)
        XCTAssertThrowsError(
            try AgentEventNormalizer.codex(
                dto,
                receivedAt: date,
                privacy: AgentPrivacyPolicy()
            )
        )
    }

    func testClaudeMapsFiveSupportedHooks() throws {
        let start = try claude(eventHint: "UserPromptSubmit", json: #"{"session_id":"s"}"#)
        let notification = try claude(eventHint: "Notification", json: #"{"session_id":"s","notification_type":"permission_prompt","message":"allow?"}"#)
        let task = try claude(eventHint: "TaskCompleted", json: #"{"session_id":"s","task_id":"task"}"#)
        let stop = try claude(eventHint: "Stop", json: #"{"session_id":"s"}"#)
        let failure = try claude(eventHint: "StopFailure", json: #"{"session_id":"s","error":"private"}"#)

        XCTAssertEqual(start.status, .running)
        XCTAssertEqual(start.turnID, "fallback")
        XCTAssertEqual(notification.status, .attentionRequired)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(stop.status, .responded)
        XCTAssertEqual(failure.status, .failed)
        XCTAssertFalse(failure.eventKeyComponent.contains("private"))
    }

    func testClaudeNotificationAllowlistRejectsOtherTypes() {
        XCTAssertThrowsError(
            try claude(
                eventHint: "Notification",
                json: #"{"session_id":"s","notification_type":"idle_prompt"}"#
            )
        )
    }

    func testClaudePromptIDIsOpaqueAndTranscriptIsIgnored() throws {
        let event = try claude(
            eventHint: "UserPromptSubmit",
            json: #"{"session_id":"s","prompt_id":"opaque-turn","transcript_path":"/secret/transcript"}"#
        )
        XCTAssertEqual(event.turnID, "opaque-turn")
        XCTAssertNil(event.projectPath)
    }

    func testNormalizedEventValidatesIdentifiersAndTime() {
        XCTAssertThrowsError(
            try NormalizedAgentEvent(
                source: .codex,
                sessionID: "",
                turnID: "turn",
                sourceEvent: "agent-turn-complete",
                eventKeyComponent: "complete",
                status: .responded,
                occurredAt: date,
                receivedAt: date,
                closesRun: true
            )
        )
        XCTAssertThrowsError(
            try NormalizedAgentEvent(
                source: .claude,
                sessionID: "s",
                turnID: String(repeating: "x", count: 129),
                sourceEvent: "Stop",
                eventKeyComponent: "stop",
                status: .responded,
                occurredAt: date,
                receivedAt: date,
                closesRun: true
            )
        )
    }

    private func claude(
        eventHint: String,
        json: String
    ) throws -> NormalizedAgentEvent {
        try AgentEventNormalizer.claude(
            JSONDecoder().decode(
                ClaudeHookDTO.self,
                from: Data(json.utf8)
            ),
            eventHint: eventHint,
            receivedAt: date,
            privacy: AgentPrivacyPolicy(),
            fallbackTurnID: "fallback"
        )
    }
}
