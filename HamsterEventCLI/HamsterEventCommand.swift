import Foundation
import MoraeCore

struct CodexNotifyRelayInvocation: Equatable {
    let previousCommand: [String]
    let payload: String

    static func parse(_ arguments: [String]) -> Self? {
        guard arguments.count == 3,
              arguments[0] == "--morae-codex-relay",
              let data = Data(base64Encoded: arguments[1]),
              let command = try? JSONDecoder().decode(
                [String].self,
                from: data
              ),
              !command.isEmpty
        else {
            return nil
        }
        return Self(
            previousCommand: command,
            payload: arguments[2]
        )
    }
}

struct HamsterEventCommand {
    private let sender: any AgentFrameSending
    private let socketURL: URL
    private let wallClock: () -> Date
    private let monotonicClock: () -> TimeInterval
    private let forwardCodexNotify: ([String], String) -> Void

    init(
        sender: any AgentFrameSending = AgentSocketClient(),
        socketURL: URL = AgentSocketLocation.url(),
        wallClock: @escaping () -> Date = Date.init,
        monotonicClock: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        forwardCodexNotify:
            @escaping ([String], String) -> Void = Self.forward
    ) {
        self.sender = sender
        self.socketURL = socketURL
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
        self.forwardCodexNotify = forwardCodexNotify
    }

    func run(
        arguments: [String],
        readStandardInput: HamsterEventInvocationParser.StandardInputReader = {
            try HamsterEventStandardInput.readLimited()
        }
    ) {
        let relay = CodexNotifyRelayInvocation.parse(arguments)
        let eventArguments = relay.map { [$0.payload] } ?? arguments
        let deadline = AgentDeadline(
            duration: AgentSocketClient.totalTimeout,
            now: monotonicClock
        )
        do {
            let invocation = try HamsterEventInvocationParser().parse(
                arguments: eventArguments,
                readStandardInput: readStandardInput
            )
            let envelope = AgentTransportEnvelope(
                source: invocation.source,
                eventHint: invocation.eventHint,
                receivedAtMs: Int64(
                    (wallClock().timeIntervalSince1970 * 1_000).rounded()
                ),
                rawPayload: invocation.rawPayload
            )
            let frame = try AgentFrameCodec.encode(envelope)
            _ = try sender.send(
                frame: frame,
                to: socketURL,
                deadline: deadline
            )
        } catch {
            // Hooks are best effort: never print, retry, or fail the agent.
        }
        if let relay {
            forwardCodexNotify(relay.previousCommand, relay.payload)
        }
    }

    private static func forward(
        command: [String],
        payload: String
    ) {
        guard let executable = command.first else { return }
        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst()) + [payload]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command + [payload]
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Preserve Morae's best-effort hook contract.
        }
    }
}
