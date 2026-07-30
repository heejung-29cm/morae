import MoraeCore
import XCTest

final class AgentIPCTests: XCTestCase {
    func testEnvelopeFrameUsesNetworkByteOrderAndRoundTrips() throws {
        let envelope = AgentTransportEnvelope(
            source: .codex,
            eventHint: "agent-turn-complete",
            receivedAtMs: 1_775_039_400_123,
            rawPayload: Data(#"{"type":"agent-turn-complete"}"#.utf8)
        )

        let frame = try AgentFrameCodec.encode(envelope)
        let header = frame.prefix(AgentIPCContract.headerByteCount)
        let bodyLength = try AgentFrameCodec.decodeBodyLength(
            from: Data(header)
        )
        let body = frame.dropFirst(AgentIPCContract.headerByteCount)

        XCTAssertEqual(bodyLength, body.count)
        XCTAssertEqual(
            try AgentFrameCodec.decodeEnvelope(from: Data(body)),
            envelope
        )
    }

    func testBodyLengthRejectsZeroAndValuesOverOneMiB() {
        XCTAssertThrowsError(
            try AgentFrameCodec.decodeBodyLength(
                from: Data([0, 0, 0, 0])
            )
        )
        XCTAssertNoThrow(
            try AgentFrameCodec.decodeBodyLength(
                from: Data([0, 16, 0, 0])
            )
        )
        XCTAssertThrowsError(
            try AgentFrameCodec.decodeBodyLength(
                from: Data([0, 16, 0, 1])
            )
        )
    }

    func testEnvelopeUsesBase64PayloadAndAckUsesContractKeys() throws {
        let envelope = AgentTransportEnvelope(
            source: .claude,
            eventHint: "Stop",
            receivedAtMs: 123,
            rawPayload: Data([0, 1, 2, 255])
        )
        let envelopeJSON = try JSONEncoder().encode(envelope)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: envelopeJSON)
                as? [String: Any]
        )
        XCTAssertEqual(object["rawPayload"] as? String, "AAEC/w==")

        let eventID = UUID(
            uuidString: "6C214FD5-AE11-4A97-8145-004CE05CE20F"
        )!
        let ackData = try JSONEncoder().encode(
            AgentIngressAck.success(eventID: eventID)
        )
        let ackObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ackData)
                as? [String: Any]
        )
        XCTAssertEqual(ackObject["ok"] as? Bool, true)
        XCTAssertEqual(
            ackObject["eventId"] as? String,
            eventID.uuidString
        )
        XCTAssertNil(ackObject["code"])
    }

    func testOversizedEncodedEnvelopeIsRejected() {
        let envelope = AgentTransportEnvelope(
            source: .codex,
            eventHint: "agent-turn-complete",
            receivedAtMs: 123,
            rawPayload: Data(
                repeating: 0,
                count: AgentIPCContract.maximumFrameBodyByteCount
            )
        )

        XCTAssertThrowsError(try AgentFrameCodec.encode(envelope))
    }
}
