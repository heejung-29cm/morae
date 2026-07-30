import Foundation
import MoraeCore

struct HamsterEventCommand {
    private let sender: any AgentFrameSending
    private let socketURL: URL
    private let wallClock: () -> Date
    private let monotonicClock: () -> TimeInterval

    init(
        sender: any AgentFrameSending = AgentSocketClient(),
        socketURL: URL = AgentSocketLocation.url(),
        wallClock: @escaping () -> Date = Date.init,
        monotonicClock: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.sender = sender
        self.socketURL = socketURL
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
    }

    func run(
        arguments: [String],
        readStandardInput: HamsterEventInvocationParser.StandardInputReader = {
            try HamsterEventStandardInput.readLimited()
        }
    ) {
        let deadline = AgentDeadline(
            duration: AgentSocketClient.totalTimeout,
            now: monotonicClock
        )
        do {
            let invocation = try HamsterEventInvocationParser().parse(
                arguments: arguments,
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
    }
}
