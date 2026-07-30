import Foundation
import GRDB
import MoraeCore
import Observation
import UserNotifications

private enum AgentMappingError: Error {
    case invalidRecord
}

struct AgentApplyResult: Equatable, Sendable {
    let run: AgentRun
    let eventID: AgentEventID
    let insertedEvent: Bool
    let shouldNotify: Bool
}

protocol AgentRepository: Sendable {
    func apply(_ event: NormalizedAgentEvent) async throws -> AgentApplyResult
    func recent(limit: Int) async throws -> [AgentRun]
    func observation(limit: Int) -> AsyncValueObservation<[AgentRun]>
    func markAllRead() async throws
    func prune(receivedBefore cutoff: Date) async throws -> Int
}

private struct AgentRunRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_runs"

    let id: String
    let source: String
    let sessionID: String
    let turnID: String
    let projectPath: String?
    let title: String?
    let status: String
    let startedAtMs: Int64?
    let receivedAtMs: Int64
    let updatedAtMs: Int64
    let closedAtMs: Int64?
    let closureReason: String?
    let lastMessage: String?
    let isUnread: Bool

    enum CodingKeys: String, CodingKey {
        case id, source, title, status
        case sessionID = "session_id"
        case turnID = "turn_id"
        case projectPath = "project_path"
        case startedAtMs = "started_at_ms"
        case receivedAtMs = "received_at_ms"
        case updatedAtMs = "updated_at_ms"
        case closedAtMs = "closed_at_ms"
        case closureReason = "closure_reason"
        case lastMessage = "last_message"
        case isUnread = "is_unread"
    }

    func domain() throws -> AgentRun {
        guard let uuid = UUID(uuidString: id),
              let source = AgentSource(rawValue: source),
              let status = AgentStatus(rawValue: status),
              closureReason == nil
                || AgentClosureReason(rawValue: closureReason!) != nil
        else {
            throw AgentMappingError.invalidRecord
        }
        return AgentRun(
            id: AgentRunID(rawValue: uuid),
            source: source,
            sessionID: sessionID,
            turnID: turnID,
            projectPath: projectPath,
            title: title,
            status: status,
            startedAt: startedAtMs.map(Date.init(unixMilliseconds:)),
            receivedAt: Date(unixMilliseconds: receivedAtMs),
            updatedAt: Date(unixMilliseconds: updatedAtMs),
            closedAt: closedAtMs.map(Date.init(unixMilliseconds:)),
            closureReason: closureReason.flatMap(AgentClosureReason.init(rawValue:)),
            lastMessage: lastMessage,
            isUnread: isUnread
        )
    }
}

final class GRDBAgentRepository: AgentRepository, @unchecked Sendable {
    private let writer: any DatabaseWriter
    private let uuidGenerator: any UUIDGenerating

    init(
        database: AppDatabase,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator()
    ) {
        writer = database.writer
        self.uuidGenerator = uuidGenerator
    }

    func apply(
        _ event: NormalizedAgentEvent
    ) async throws -> AgentApplyResult {
        let generatedTurnID = uuidGenerator.next().uuidString.lowercased()
        let runID = AgentRunID(rawValue: uuidGenerator.next())
        let eventID = AgentEventID(rawValue: uuidGenerator.next())
        return try await writer.write { database in
            let turnID = try Self.resolveTurnID(
                event,
                generated: generatedTurnID,
                database: database
            )
            let eventKey = [
                event.source.rawValue,
                event.sessionID,
                turnID,
                event.eventKeyComponent,
            ].joined(separator: ":")

            if let existingEventID = try String.fetchOne(
                database,
                sql: "SELECT id FROM agent_events WHERE event_key = ?",
                arguments: [eventKey]
            ), let existingUUID = UUID(uuidString: existingEventID),
               let record = try Self.fetchRun(
                   source: event.source,
                   sessionID: event.sessionID,
                   turnID: turnID,
                   database: database
               ) {
                return AgentApplyResult(
                    run: try record.domain(),
                    eventID: AgentEventID(rawValue: existingUUID),
                    insertedEvent: false,
                    shouldNotify: false
                )
            }

            if event.startsRun {
                try database.execute(
                    sql: """
                        UPDATE agent_runs
                        SET closed_at_ms = ?,
                            closure_reason = 'superseded',
                            updated_at_ms = ?
                        WHERE source = ?
                          AND session_id = ?
                          AND turn_id <> ?
                          AND closed_at_ms IS NULL
                        """,
                    arguments: [
                        event.receivedAt.unixMilliseconds,
                        event.receivedAt.unixMilliseconds,
                        event.source.rawValue,
                        event.sessionID,
                        turnID,
                    ]
                )
            }

            let existing = try Self.fetchRun(
                source: event.source,
                sessionID: event.sessionID,
                turnID: turnID,
                database: database
            )
            let previousStatus = existing.flatMap {
                AgentStatus(rawValue: $0.status)
            }
            let advancesStatus = previousStatus.map {
                event.status.rank > $0.rank
            } ?? true
            let storedStatus = advancesStatus
                ? event.status
                : previousStatus ?? event.status
            let storedRunID = existing?.id ?? runID.storageValue

            if existing == nil {
                try database.execute(
                    sql: """
                        INSERT INTO agent_runs (
                            id, source, session_id, turn_id, project_path,
                            title, status, started_at_ms, received_at_ms,
                            updated_at_ms, closed_at_ms, closure_reason,
                            last_message, is_unread
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                        """,
                    arguments: [
                        storedRunID,
                        event.source.rawValue,
                        event.sessionID,
                        turnID,
                        event.projectPath,
                        event.title,
                        storedStatus.rawValue,
                        event.startsRun
                            ? event.occurredAt.unixMilliseconds : nil,
                        event.receivedAt.unixMilliseconds,
                        event.receivedAt.unixMilliseconds,
                        event.closesRun
                            ? event.occurredAt.unixMilliseconds : nil,
                        event.closesRun
                            ? AgentClosureReason.terminalEvent.rawValue : nil,
                        event.lastMessage,
                    ]
                )
            } else {
                try database.execute(
                    sql: """
                        UPDATE agent_runs
                        SET status = ?,
                            project_path = COALESCE(?, project_path),
                            title = COALESCE(?, title),
                            last_message = COALESCE(?, last_message),
                            updated_at_ms = ?,
                            closed_at_ms = CASE WHEN ? THEN ? ELSE closed_at_ms END,
                            closure_reason = CASE WHEN ? THEN 'terminal_event' ELSE closure_reason END,
                            is_unread = 1
                        WHERE id = ?
                        """,
                    arguments: [
                        storedStatus.rawValue,
                        event.projectPath,
                        event.title,
                        event.lastMessage,
                        event.receivedAt.unixMilliseconds,
                        event.closesRun,
                        event.occurredAt.unixMilliseconds,
                        event.closesRun,
                        storedRunID,
                    ]
                )
            }

            try database.execute(
                sql: """
                    INSERT INTO agent_events (
                        id, agent_run_id, event_key, source_event,
                        normalized_status, occurred_at_ms, received_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    eventID.storageValue,
                    storedRunID,
                    eventKey,
                    event.sourceEvent,
                    event.status.rawValue,
                    event.occurredAt.unixMilliseconds,
                    event.receivedAt.unixMilliseconds,
                ]
            )
            let stored = try AgentRunRecord.fetchOne(
                database,
                key: storedRunID
            )!
            return AgentApplyResult(
                run: try stored.domain(),
                eventID: eventID,
                insertedEvent: true,
                shouldNotify: advancesStatus
                    && event.status != .running
                    && event.status != .cancelled
            )
        }
    }

    func recent(limit: Int) async throws -> [AgentRun] {
        try await writer.read { database in
            try AgentRunRecord.fetchAll(
                database,
                sql: """
                    SELECT * FROM agent_runs
                    ORDER BY updated_at_ms DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [max(0, limit)]
            ).map { try $0.domain() }
        }
    }

    func observation(
        limit: Int
    ) -> AsyncValueObservation<[AgentRun]> {
        ValueObservation.tracking { database in
            try AgentRunRecord.fetchAll(
                database,
                sql: """
                    SELECT * FROM agent_runs
                    ORDER BY updated_at_ms DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [max(0, limit)]
            ).map { try $0.domain() }
        }
        .values(in: writer)
    }

    func markAllRead() async throws {
        try await writer.write { database in
            try database.execute(
                sql: "UPDATE agent_runs SET is_unread = 0 WHERE is_unread = 1"
            )
        }
    }

    func prune(receivedBefore cutoff: Date) async throws -> Int {
        try await writer.write { database in
            try database.execute(
                sql: "DELETE FROM agent_runs WHERE received_at_ms < ?",
                arguments: [cutoff.unixMilliseconds]
            )
            return database.changesCount
        }
    }

    private static func resolveTurnID(
        _ event: NormalizedAgentEvent,
        generated: String,
        database: Database
    ) throws -> String {
        if let turnID = event.turnID {
            return turnID
        }
        return try String.fetchOne(
            database,
            sql: """
                SELECT turn_id FROM agent_runs
                WHERE source = ? AND session_id = ? AND closed_at_ms IS NULL
                ORDER BY updated_at_ms DESC LIMIT 1
                """,
            arguments: [event.source.rawValue, event.sessionID]
        ) ?? generated
    }

    private static func fetchRun(
        source: AgentSource,
        sessionID: String,
        turnID: String,
        database: Database
    ) throws -> AgentRunRecord? {
        try AgentRunRecord.fetchOne(
            database,
            sql: """
                SELECT * FROM agent_runs
                WHERE source = ? AND session_id = ? AND turn_id = ?
                """,
            arguments: [source.rawValue, sessionID, turnID]
        )
    }
}

protocol AgentPrivacyPolicyProviding: Sendable {
    func policy() -> AgentPrivacyPolicy
}

struct UserDefaultsAgentPrivacyPolicyProvider:
    AgentPrivacyPolicyProviding,
    @unchecked Sendable
{
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func policy() -> AgentPrivacyPolicy {
        AgentPrivacyPolicy(
            storeProjectPath: defaults.bool(
                forKey: "privacy.storeProjectPath"
            ),
            storeAgentTitle: defaults.bool(
                forKey: "privacy.storeAgentTitle"
            ),
            storeLastMessage: defaults.bool(
                forKey: "privacy.storeLastMessage"
            ),
            showDetailsInNotification: defaults.bool(
                forKey: "privacy.showDetailsInNotification"
            )
        )
    }
}

enum AgentNotificationAuthorizationState: Equatable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

protocol AgentNotifying: Sendable {
    func notify(for run: AgentRun) async
    func authorizationState() async -> AgentNotificationAuthorizationState
    func requestAuthorization() async -> Bool
}

struct SystemAgentNotifier: AgentNotifying {
    func authorizationState() async -> AgentNotificationAuthorizationState {
        let status = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notify(for run: AgentRun) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: run)
        content.body = Self.body(for: run.status)
        content.categoryIdentifier = "MORAE_AGENT_EVENT"
        content.userInfo = ["destination": "agent-list"]
        let request = UNNotificationRequest(
            identifier: "agent-\(run.id.storageValue)-\(run.status.rawValue)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    static func title(for run: AgentRun) -> String {
        let source = run.source == .codex ? "Codex" : "Claude"
        return switch run.status {
        case .responded: "\(source) 응답이 끝났어요."
        case .completed: "\(source) 작업이 완료됐어요."
        case .failed: "\(source) 작업이 중단됐어요."
        case .attentionRequired: "\(source) 확인이 필요해요."
        case .running, .cancelled: "\(source) 상태가 변경됐어요."
        }
    }

    static func body(for status: AgentStatus) -> String {
        switch status {
        case .failed:
            "모래에서 상태를 확인해 주세요."
        case .attentionRequired:
            "에이전트 화면을 확인해 주세요."
        case .running, .responded, .completed, .cancelled:
            "모래에서 최근 기록을 확인해 주세요."
        }
    }
}

actor AgentRetentionService {
    private let repository: any AgentRepository
    private let clock: any Clock
    private let defaults: UserDefaults
    private let key = "maintenance.lastAgentPruneAtMs"

    init(
        repository: any AgentRepository,
        clock: any Clock,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.clock = clock
        self.defaults = defaults
    }

    func pruneIfNeeded(force: Bool = false) async {
        let now = clock.now()
        let last = defaults.object(forKey: key) as? NSNumber
        guard force || last == nil
            || now.unixMilliseconds - last!.int64Value >= 86_400_000 else {
            return
        }
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        if (try? await repository.prune(receivedBefore: cutoff)) != nil {
            defaults.set(now.unixMilliseconds, forKey: key)
        }
    }
}

actor ReceiveAgentEvent {
    private let repository: any AgentRepository
    private let privacy: any AgentPrivacyPolicyProviding
    private let notifier: any AgentNotifying
    private let retention: AgentRetentionService
    private let uuidGenerator: any UUIDGenerating

    init(
        repository: any AgentRepository,
        privacy: any AgentPrivacyPolicyProviding,
        notifier: any AgentNotifying,
        retention: AgentRetentionService,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator()
    ) {
        self.repository = repository
        self.privacy = privacy
        self.notifier = notifier
        self.retention = retention
        self.uuidGenerator = uuidGenerator
    }

    func execute(
        _ envelope: AgentTransportEnvelope
    ) async -> AgentIngressAck {
        guard envelope.transportVersion == AgentIPCContract.transportVersion
        else {
            return .failure(.unsupportedTransport)
        }
        do {
            let receivedAt = Date(
                unixMilliseconds: envelope.receivedAtMs
            )
            let event: NormalizedAgentEvent
            switch envelope.source {
            case .codex:
                let dto = try JSONDecoder().decode(
                    CodexNotifyDTO.self,
                    from: envelope.rawPayload
                )
                event = try AgentEventNormalizer.codex(
                    dto,
                    receivedAt: receivedAt,
                    privacy: privacy.policy()
                )
            case .claude:
                let dto = try JSONDecoder().decode(
                    ClaudeHookDTO.self,
                    from: envelope.rawPayload
                )
                event = try AgentEventNormalizer.claude(
                    dto,
                    eventHint: envelope.eventHint,
                    receivedAt: receivedAt,
                    privacy: privacy.policy(),
                    fallbackTurnID: uuidGenerator.next()
                        .uuidString.lowercased()
                )
            }
            let result = try await repository.apply(event)
            if result.insertedEvent && result.shouldNotify {
                await notifier.notify(for: result.run)
            }
            await retention.pruneIfNeeded()
            return .success(eventID: result.eventID.rawValue)
        } catch is DecodingError {
            return .failure(.invalidPayload)
        } catch is NormalizedAgentEventError {
            return .failure(.unsupportedEvent)
        } catch {
            return .failure(.persistenceFailed)
        }
    }
}

struct ReceiveAgentEnvelopeHandler: AgentEnvelopeHandling {
    let receiver: ReceiveAgentEvent

    func handle(
        _ envelope: AgentTransportEnvelope
    ) async -> AgentIngressAck {
        await receiver.execute(envelope)
    }
}

@MainActor
@Observable
final class AgentActivityModel {
    private(set) var runs: [AgentRun] = []
    private(set) var hasUnread = false
    private(set) var errorMessage: String?
    private(set) var notificationAuthorization:
        AgentNotificationAuthorizationState = .unknown

    private let repository: any AgentRepository
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    private var isVisible = false

    init(repository: any AgentRepository) {
        self.repository = repository
        start()
    }

    deinit {
        observationTask?.cancel()
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            Task { await markAllRead() }
        }
    }

    func requestNotificationAuthorization(
        notifier: any AgentNotifying
    ) async -> Bool {
        let granted = await notifier.requestAuthorization()
        notificationAuthorization = await notifier.authorizationState()
        return granted
    }

    func refreshNotificationAuthorization(
        notifier: any AgentNotifying
    ) async {
        notificationAuthorization = await notifier.authorizationState()
    }

    private func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self, repository] in
            do {
                for try await values in repository.observation(limit: 20) {
                    guard !Task.isCancelled else { return }
                    self?.runs = values
                    self?.hasUnread = values.contains(where: \.isUnread)
                    self?.errorMessage = nil
                    if self?.isVisible == true {
                        await self?.markAllRead()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = "에이전트 기록을 불러오지 못했습니다."
            }
        }
    }

    private func markAllRead() async {
        do {
            try await repository.markAllRead()
            runs = runs.map {
                var run = $0
                run.isUnread = false
                return run
            }
            hasUnread = false
        } catch {
            errorMessage = "에이전트 기록을 읽음 처리하지 못했습니다."
        }
    }
}
