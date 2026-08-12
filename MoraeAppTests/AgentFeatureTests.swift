import Foundation
import GRDB
import MoraeCore
@testable import MoraeApp
import XCTest

final class AgentFeatureTests: XCTestCase {
    private final class SequenceUUIDGenerator:
        UUIDGenerating,
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var value: UInt64 = 1

        func next() -> UUID {
            lock.lock()
            defer { lock.unlock() }
            let uuid = UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0,
                    UInt8((value >> 8) & 0xff),
                    UInt8(value & 0xff)
                )
            )
            value += 1
            return uuid
        }
    }

    private actor StubNotifier: AgentNotifying {
        private(set) var runs: [AgentRun] = []

        func notify(for run: AgentRun) async {
            runs.append(run)
        }

        func authorizationState() async
            -> AgentNotificationAuthorizationState {
            .authorized
        }

        func requestAuthorization() async -> Bool {
            true
        }

        func count() -> Int {
            runs.count
        }
    }

    private struct FixedPrivacy: AgentPrivacyPolicyProviding {
        func policy() -> AgentPrivacyPolicy {
            AgentPrivacyPolicy()
        }
    }

    private let date = Date(unixMilliseconds: 1_800_000_000_000)

    func testRepositoryCorrelatesMissingClaudeTurnAndPreventsDowngrade()
        async throws {
        let fixture = try TemporaryDatabase()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: SequenceUUIDGenerator()
        )
        let start = try event(
            turnID: "turn",
            sourceEvent: "UserPromptSubmit",
            component: "start",
            status: .running,
            starts: true
        )
        let completed = try event(
            turnID: nil,
            sourceEvent: "TaskCompleted",
            component: "task:1",
            status: .completed
        )
        let stop = try event(
            turnID: nil,
            sourceEvent: "Stop",
            component: "stop",
            status: .responded,
            closes: true
        )

        _ = try await repository.apply(start)
        let completedResult = try await repository.apply(completed)
        let stoppedResult = try await repository.apply(stop)

        XCTAssertEqual(completedResult.run.turnID, "turn")
        XCTAssertEqual(stoppedResult.run.status, .completed)
        XCTAssertEqual(stoppedResult.run.closureReason, .terminalEvent)
        XCTAssertNotNil(stoppedResult.run.closedAt)
        XCTAssertFalse(stoppedResult.shouldNotify)
    }

    func testRepositoryDeduplicatesEventKeyAndSupersedesOpenTurn()
        async throws {
        let fixture = try TemporaryDatabase()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: SequenceUUIDGenerator()
        )
        let first = try event(
            turnID: "one",
            sourceEvent: "UserPromptSubmit",
            component: "start",
            status: .running,
            starts: true
        )
        let second = try event(
            turnID: "two",
            sourceEvent: "UserPromptSubmit",
            component: "start",
            status: .running,
            starts: true
        )

        let inserted = try await repository.apply(first)
        let duplicate = try await repository.apply(first)
        _ = try await repository.apply(second)
        let runs = try await repository.recent(limit: 20)

        XCTAssertTrue(inserted.insertedEvent)
        XCTAssertFalse(duplicate.insertedEvent)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(
            runs.first(where: { $0.turnID == "one" })?.closureReason,
            .superseded
        )
    }

    func testPruneUsesStrictNinetyDayBoundaryAndCascadesEvents()
        async throws {
        let fixture = try TemporaryDatabase()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: SequenceUUIDGenerator()
        )
        _ = try await repository.apply(
            event(
                turnID: "old",
                sourceEvent: "Stop",
                component: "old",
                status: .responded,
                closes: true,
                receivedAt: date.addingTimeInterval(-90 * 86_400 - 1)
            )
        )
        _ = try await repository.apply(
            event(
                turnID: "boundary",
                sourceEvent: "Stop",
                component: "boundary",
                status: .responded,
                closes: true,
                receivedAt: date.addingTimeInterval(-90 * 86_400)
            )
        )

        let prunedCount = try await repository.prune(
            receivedBefore: date.addingTimeInterval(-90 * 86_400)
        )
        XCTAssertEqual(prunedCount, 1)
        let remainingRuns = try await repository.recent(limit: 20)
        XCTAssertEqual(remainingRuns.count, 1)
        XCTAssertEqual(
            try fixture.database.read {
                try Int.fetchOne(
                    $0,
                    sql: "SELECT COUNT(*) FROM agent_events"
                )
            },
            1
        )
    }

    func testPrivacyScrubClearsSelectedColumnsInOneUpdate() async throws {
        let fixture = try TemporaryDatabase()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: SequenceUUIDGenerator()
        )
        let privateEvent = try NormalizedAgentEvent(
            source: .claude,
            sessionID: "private-session",
            turnID: "private-turn",
            sourceEvent: "TaskCompleted",
            eventKeyComponent: "task:private",
            status: .completed,
            occurredAt: date,
            receivedAt: date,
            closesRun: false,
            startsRun: false,
            projectPath: "/private/project",
            title: "private title",
            lastMessage: "private message"
        )
        _ = try await repository.apply(privateEvent)

        try await repository.scrub([.projectPath, .lastMessage])

        let recentRuns = try await repository.recent(limit: 1)
        let run = try XCTUnwrap(recentRuns.first)
        XCTAssertNil(run.projectPath)
        XCTAssertEqual(run.title, "private title")
        XCTAssertNil(run.lastMessage)
    }

    func testRetentionRunsAtMostOncePerDayUnlessForced() async throws {
        let fixture = try TemporaryDatabase()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: SequenceUUIDGenerator()
        )
        let defaults = UserDefaults(
            suiteName: "AgentFeatureTests.\(UUID().uuidString)"
        )!
        let oldDate = date.addingTimeInterval(-91 * 86_400)
        _ = try await repository.apply(
            event(
                turnID: "first-old",
                sourceEvent: "Stop",
                component: "first-old",
                status: .responded,
                closes: true,
                receivedAt: oldDate
            )
        )
        let retention = AgentRetentionService(
            repository: repository,
            clock: FixedClock(instant: date),
            defaults: defaults
        )

        await retention.pruneIfNeeded()
        _ = try await repository.apply(
            event(
                turnID: "second-old",
                sourceEvent: "Stop",
                component: "second-old",
                status: .responded,
                closes: true,
                receivedAt: oldDate
            )
        )
        await retention.pruneIfNeeded()
        let runsBeforeForcedPrune = try await repository.recent(limit: 20)
        XCTAssertEqual(runsBeforeForcedPrune.count, 1)

        await retention.pruneIfNeeded(force: true)
        let runsAfterForcedPrune = try await repository.recent(limit: 20)
        XCTAssertTrue(runsAfterForcedPrune.isEmpty)
    }

    func testReceiveAgentEventStoresOnceAndNotifiesOnce() async throws {
        let fixture = try TemporaryDatabase()
        let generator = SequenceUUIDGenerator()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: generator
        )
        let notifier = StubNotifier()
        let defaults = UserDefaults(
            suiteName: "AgentFeatureTests.\(UUID().uuidString)"
        )!
        let receiver = ReceiveAgentEvent(
            repository: repository,
            privacy: FixedPrivacy(),
            notifier: notifier,
            retention: AgentRetentionService(
                repository: repository,
                clock: FixedClock(instant: date),
                defaults: defaults
            ),
            uuidGenerator: generator
        )
        let payload = Data(
            #"""
            {
              "type": "agent-turn-complete",
              "thread-id": "thread",
              "turn-id": "turn",
              "cwd": "/private/project",
              "input-messages": ["private title"],
              "last-assistant-message": "private result"
            }
            """#.utf8
        )
        let envelope = AgentTransportEnvelope(
            source: .codex,
            eventHint: "agent-turn-complete",
            receivedAtMs: date.unixMilliseconds,
            rawPayload: payload
        )

        let first = await receiver.execute(envelope)
        let duplicate = await receiver.execute(envelope)

        XCTAssertTrue(first.ok)
        XCTAssertTrue(duplicate.ok)
        let storedRuns = try await repository.recent(limit: 20)
        let notificationCount = await notifier.count()
        XCTAssertEqual(storedRuns.count, 1)
        XCTAssertEqual(notificationCount, 1)
        XCTAssertNil(storedRuns[0].projectPath)
        XCTAssertNil(storedRuns[0].title)
        XCTAssertNil(storedRuns[0].lastMessage)
    }

    func testReceiveRejectsUnsupportedClaudeNotificationBeforeSave()
        async throws {
        let fixture = try TemporaryDatabase()
        let repository = GRDBAgentRepository(database: fixture.database)
        let notifier = StubNotifier()
        let defaults = UserDefaults(
            suiteName: "AgentFeatureTests.\(UUID().uuidString)"
        )!
        let receiver = ReceiveAgentEvent(
            repository: repository,
            privacy: FixedPrivacy(),
            notifier: notifier,
            retention: AgentRetentionService(
                repository: repository,
                clock: FixedClock(instant: date),
                defaults: defaults
            )
        )
        let envelope = AgentTransportEnvelope(
            source: .claude,
            eventHint: "Notification",
            receivedAtMs: date.unixMilliseconds,
            rawPayload: Data(#"{"session_id":"s","notification_type":"idle_prompt"}"#.utf8)
        )

        let ack = await receiver.execute(envelope)

        XCTAssertEqual(ack, .failure(.unsupportedEvent))
        let storedRuns = try await repository.recent(limit: 20)
        let notificationCount = await notifier.count()
        XCTAssertTrue(storedRuns.isEmpty)
        XCTAssertEqual(notificationCount, 0)
    }

    func testNotificationCopyDoesNotContainStoredDetails() {
        let run = AgentRun(
            id: AgentRunID(rawValue: UUID()),
            source: .claude,
            sessionID: "session",
            turnID: "turn",
            title: "private title",
            status: .completed,
            receivedAt: date,
            updatedAt: date,
            lastMessage: "private result"
        )
        XCTAssertEqual(
            SystemAgentNotifier.title(for: run),
            "Claude 작업이 완료됐어요."
        )
        XCTAssertFalse(
            SystemAgentNotifier.body(for: run.status).contains("private")
        )
    }

    func testAgentActivityObservesUnreadAndMarksVisibleRunsRead()
        async throws {
        let fixture = try TemporaryDatabase()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: SequenceUUIDGenerator()
        )
        let model = await MainActor.run {
            AgentActivityModel(repository: repository)
        }

        _ = try await repository.apply(
            event(
                turnID: "observed",
                sourceEvent: "Stop",
                component: "observed",
                status: .responded,
                closes: true
            )
        )
        for _ in 0..<100 {
            let observed = await MainActor.run {
                model.runs.count == 1 && model.hasUnread
            }
            if observed { break }
            await Task.yield()
        }
        let hasUnreadBeforeOpening = await MainActor.run {
            model.hasUnread
        }
        XCTAssertTrue(hasUnreadBeforeOpening)
        let animatesBeforeOpening = await MainActor.run {
            model.shouldAnimateMenuBarIcon
        }
        XCTAssertTrue(animatesBeforeOpening)

        await MainActor.run {
            model.setVisible(true)
        }
        for _ in 0..<100 {
            if await MainActor.run(body: { !model.hasUnread }) {
                break
            }
            await Task.yield()
        }
        let hasUnreadAfterOpening = await MainActor.run {
            model.hasUnread
        }
        XCTAssertFalse(hasUnreadAfterOpening)
        let animatesAfterOpening = await MainActor.run {
            model.shouldAnimateMenuBarIcon
        }
        XCTAssertFalse(animatesAfterOpening)
        let storedRuns = try await repository.recent(limit: 20)
        XCTAssertEqual(
            storedRuns.first?.isUnread,
            false
        )

        _ = try await repository.apply(
            event(
                turnID: "active",
                sourceEvent: "UserPromptSubmit",
                component: "active-start",
                status: .running,
                starts: true
            )
        )
        for _ in 0..<100 {
            let isReadButRunning = await MainActor.run {
                !model.hasUnread
                    && model.runs.contains { $0.status == .running }
            }
            if isReadButRunning { break }
            await Task.yield()
        }
        let animatesWhileRunning = await MainActor.run {
            model.shouldAnimateMenuBarIcon
        }
        XCTAssertTrue(animatesWhileRunning)

        _ = try await repository.apply(
            event(
                turnID: "active",
                sourceEvent: "Stop",
                component: "active-stop",
                status: .responded,
                closes: true
            )
        )
        for _ in 0..<100 {
            let hasStopped = await MainActor.run {
                !model.hasUnread
                    && !model.runs.contains { $0.status == .running }
            }
            if hasStopped { break }
            await Task.yield()
        }
        let animatesAfterStop = await MainActor.run {
            model.shouldAnimateMenuBarIcon
        }
        XCTAssertFalse(animatesAfterStop)
    }

    func testCodexAndClaudeFixturesRoundTripThroughSocket() async throws {
        let fixture = try TemporaryDatabase()
        let generator = SequenceUUIDGenerator()
        let repository = GRDBAgentRepository(
            database: fixture.database,
            uuidGenerator: generator
        )
        let notifier = StubNotifier()
        let defaults = UserDefaults(
            suiteName: "AgentFeatureTests.\(UUID().uuidString)"
        )!
        let receiver = ReceiveAgentEvent(
            repository: repository,
            privacy: FixedPrivacy(),
            notifier: notifier,
            retention: AgentRetentionService(
                repository: repository,
                clock: FixedClock(instant: date),
                defaults: defaults
            ),
            uuidGenerator: generator
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let endpoint = directory.appendingPathComponent("event.sock")
        let server = AgentSocketServer(
            endpointURL: endpoint,
            handler: ReceiveAgentEnvelopeHandler(receiver: receiver)
        )
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        try server.start()

        let fixtures: [(String, AgentSource, String)] = [
            ("codex-agent-turn-complete", .codex, "agent-turn-complete"),
            ("claude-user-prompt-submit", .claude, "UserPromptSubmit"),
            ("claude-notification", .claude, "Notification"),
            ("claude-task-completed", .claude, "TaskCompleted"),
            ("claude-stop", .claude, "Stop"),
        ]
        for (name, source, hint) in fixtures {
            let ack = try AgentSocketClient().send(
                frame: AgentFrameCodec.encode(
                    AgentTransportEnvelope(
                        source: source,
                        eventHint: hint,
                        receivedAtMs: date.unixMilliseconds,
                        rawPayload: try FixtureLoader.data(
                            named: name,
                            extension: "json"
                        )
                    )
                ),
                to: endpoint,
                deadline: AgentDeadline(duration: 1)
            )
            XCTAssertTrue(ack.ok, "\(name) should receive a success ACK")
        }

        let runs = try await repository.recent(limit: 20)
        let codexRun = try XCTUnwrap(
            runs.first { $0.source == .codex }
        )
        let claudeRun = try XCTUnwrap(
            runs.first { $0.source == .claude }
        )
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(codexRun.turnID, "codex-turn-fixture")
        XCTAssertEqual(codexRun.status, .responded)
        XCTAssertEqual(claudeRun.turnID, "claude-turn-fixture")
        XCTAssertEqual(claudeRun.status, .completed)
        XCTAssertNotNil(claudeRun.closedAt)
        let notificationCount = await notifier.count()
        XCTAssertEqual(notificationCount, 3)
        XCTAssertEqual(
            try fixture.database.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM agent_events")
            },
            5
        )
    }

    private func event(
        turnID: String?,
        sourceEvent: String,
        component: String,
        status: AgentStatus,
        closes: Bool = false,
        starts: Bool = false,
        receivedAt: Date? = nil
    ) throws -> NormalizedAgentEvent {
        let instant = receivedAt ?? date
        return try NormalizedAgentEvent(
            source: .claude,
            sessionID: "session",
            turnID: turnID,
            sourceEvent: sourceEvent,
            eventKeyComponent: component,
            status: status,
            occurredAt: instant,
            receivedAt: instant,
            closesRun: closes,
            startsRun: starts
        )
    }
}
