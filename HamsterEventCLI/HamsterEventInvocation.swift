import Foundation
import MoraeCore

struct HamsterEventInvocation: Equatable, Sendable {
    let source: AgentSource
    let eventHint: String
    let rawPayload: Data
}

enum HamsterEventInvocationError: Error, Equatable {
    case invalidArguments
    case invalidPayload
    case payloadTooLarge
}

struct HamsterEventInvocationParser {
    typealias StandardInputReader = () throws -> Data

    private static let claudeEventHints = [
        "claude-turn-start": "UserPromptSubmit",
        "claude-notification": "Notification",
        "claude-task-completed": "TaskCompleted",
        "claude-stop": "Stop",
        "claude-stop-failure": "StopFailure",
    ]

    func parse(
        arguments: [String],
        readStandardInput: StandardInputReader
    ) throws -> HamsterEventInvocation {
        guard arguments.count == 1 else {
            throw HamsterEventInvocationError.invalidArguments
        }

        if let eventHint = Self.claudeEventHints[arguments[0]] {
            return HamsterEventInvocation(
                source: .claude,
                eventHint: eventHint,
                rawPayload: try validatedPayload(readStandardInput())
            )
        }

        guard let payload = arguments[0].data(using: .utf8) else {
            throw HamsterEventInvocationError.invalidPayload
        }
        return HamsterEventInvocation(
            source: .codex,
            eventHint: "agent-turn-complete",
            rawPayload: try validatedPayload(payload)
        )
    }

    private func validatedPayload(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else {
            throw HamsterEventInvocationError.invalidPayload
        }
        guard payload.count <= AgentIPCContract.maximumRawPayloadByteCount
        else {
            throw HamsterEventInvocationError.payloadTooLarge
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: payload),
            object is [String: Any]
        else {
            throw HamsterEventInvocationError.invalidPayload
        }
        return payload
    }
}

enum HamsterEventStandardInput {
    static func readLimited(
        from handle: FileHandle = .standardInput
    ) throws -> Data {
        let maximum = AgentIPCContract.maximumRawPayloadByteCount
        return try handle.read(upToCount: maximum + 1) ?? Data()
    }
}
