import Foundation

public enum AgentIPCContract {
    public static let transportVersion = 1
    public static let headerByteCount = 4
    public static let maximumRawPayloadByteCount = 760 * 1_024
    public static let maximumFrameBodyByteCount = 1_048_576
    public static let maximumAckByteCount = 4_096
}

public struct AgentTransportEnvelope: Codable, Equatable, Sendable {
    public let transportVersion: Int
    public let source: AgentSource
    public let eventHint: String
    public let receivedAtMs: Int64
    public let rawPayload: Data

    public init(
        transportVersion: Int = AgentIPCContract.transportVersion,
        source: AgentSource,
        eventHint: String,
        receivedAtMs: Int64,
        rawPayload: Data
    ) {
        self.transportVersion = transportVersion
        self.source = source
        self.eventHint = eventHint
        self.receivedAtMs = receivedAtMs
        self.rawPayload = rawPayload
    }
}

public struct AgentIngressAck: Codable, Equatable, Sendable {
    public let ok: Bool
    public let eventID: UUID?
    public let code: AgentIngressErrorCode?

    private enum CodingKeys: String, CodingKey {
        case ok
        case eventID = "eventId"
        case code
    }

    public static func success(eventID: UUID) -> AgentIngressAck {
        AgentIngressAck(ok: true, eventID: eventID, code: nil)
    }

    public static func failure(
        _ code: AgentIngressErrorCode
    ) -> AgentIngressAck {
        AgentIngressAck(ok: false, eventID: nil, code: code)
    }

    public init(
        ok: Bool,
        eventID: UUID?,
        code: AgentIngressErrorCode?
    ) {
        self.ok = ok
        self.eventID = eventID
        self.code = code
    }
}

public enum AgentFrameError: Error, Equatable, Sendable {
    case invalidHeader
    case invalidBodyLength(Int)
    case invalidEnvelope
}

public enum AgentFrameCodec {
    public static func encode(
        _ envelope: AgentTransportEnvelope,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        let body: Data
        do {
            body = try encoder.encode(envelope)
        } catch {
            throw AgentFrameError.invalidEnvelope
        }
        try validateBodyLength(body.count)

        var networkLength = UInt32(body.count).bigEndian
        var frame = Data(capacity: AgentIPCContract.headerByteCount + body.count)
        withUnsafeBytes(of: &networkLength) {
            frame.append(contentsOf: $0)
        }
        frame.append(body)
        return frame
    }

    public static func decodeBodyLength(from header: Data) throws -> Int {
        guard header.count == AgentIPCContract.headerByteCount else {
            throw AgentFrameError.invalidHeader
        }
        let length = header.reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        let bodyLength = Int(length)
        try validateBodyLength(bodyLength)
        return bodyLength
    }

    public static func decodeEnvelope(
        from body: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AgentTransportEnvelope {
        try validateBodyLength(body.count)
        do {
            return try decoder.decode(AgentTransportEnvelope.self, from: body)
        } catch {
            throw AgentFrameError.invalidEnvelope
        }
    }

    private static func validateBodyLength(_ length: Int) throws {
        guard (1...AgentIPCContract.maximumFrameBodyByteCount)
            .contains(length)
        else {
            throw AgentFrameError.invalidBodyLength(length)
        }
    }
}
