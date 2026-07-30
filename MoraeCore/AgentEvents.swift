import CryptoKit
import Foundation

public struct AgentRun: Identifiable, Equatable, Sendable {
    public let id: AgentRunID
    public let source: AgentSource
    public let sessionID: String
    public let turnID: String
    public var projectPath: String?
    public var title: String?
    public var status: AgentStatus
    public var startedAt: Date?
    public let receivedAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
    public var closureReason: AgentClosureReason?
    public var lastMessage: String?
    public var isUnread: Bool

    public init(
        id: AgentRunID,
        source: AgentSource,
        sessionID: String,
        turnID: String,
        projectPath: String? = nil,
        title: String? = nil,
        status: AgentStatus,
        startedAt: Date? = nil,
        receivedAt: Date,
        updatedAt: Date,
        closedAt: Date? = nil,
        closureReason: AgentClosureReason? = nil,
        lastMessage: String? = nil,
        isUnread: Bool = true
    ) {
        self.id = id
        self.source = source
        self.sessionID = sessionID
        self.turnID = turnID
        self.projectPath = projectPath
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.receivedAt = receivedAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.closureReason = closureReason
        self.lastMessage = lastMessage
        self.isUnread = isUnread
    }
}

public struct AgentEvent: Identifiable, Equatable, Sendable {
    public let id: AgentEventID
    public let agentRunID: AgentRunID
    public let eventKey: String
    public let sourceEvent: String
    public let normalizedStatus: AgentStatus
    public let occurredAt: Date
    public let receivedAt: Date
}

public struct AgentPrivacyPolicy: Equatable, Sendable {
    public let storeProjectPath: Bool
    public let storeAgentTitle: Bool
    public let storeLastMessage: Bool
    public let showDetailsInNotification: Bool

    public init(
        storeProjectPath: Bool = false,
        storeAgentTitle: Bool = false,
        storeLastMessage: Bool = false,
        showDetailsInNotification: Bool = false
    ) {
        self.storeProjectPath = storeProjectPath
        self.storeAgentTitle = storeAgentTitle
        self.storeLastMessage = storeLastMessage
        self.showDetailsInNotification = showDetailsInNotification
    }
}

public enum NormalizedAgentEventError: Error, Equatable, Sendable {
    case invalidSessionID
    case invalidTurnID
    case invalidSourceEvent
    case invalidTime
}

public struct NormalizedAgentEvent: Equatable, Sendable {
    public let source: AgentSource
    public let sessionID: String
    public let turnID: String?
    public let sourceEvent: String
    public let eventKeyComponent: String
    public let status: AgentStatus
    public let occurredAt: Date
    public let receivedAt: Date
    public let closesRun: Bool
    public let startsRun: Bool
    public let projectPath: String?
    public let title: String?
    public let lastMessage: String?

    public init(
        source: AgentSource,
        sessionID: String,
        turnID: String?,
        sourceEvent: String,
        eventKeyComponent: String,
        status: AgentStatus,
        occurredAt: Date,
        receivedAt: Date,
        closesRun: Bool,
        startsRun: Bool = false,
        projectPath: String? = nil,
        title: String? = nil,
        lastMessage: String? = nil
    ) throws {
        let sessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty, sessionID.count <= 256 else {
            throw NormalizedAgentEventError.invalidSessionID
        }
        let normalizedTurnID = turnID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedTurnID,
           normalizedTurnID.isEmpty || normalizedTurnID.count > 128 {
            throw NormalizedAgentEventError.invalidTurnID
        }
        let allowed: Set<String> = source == .codex
            ? ["agent-turn-complete"]
            : ["UserPromptSubmit", "Notification", "TaskCompleted", "Stop", "StopFailure"]
        guard allowed.contains(sourceEvent), !eventKeyComponent.isEmpty else {
            throw NormalizedAgentEventError.invalidSourceEvent
        }
        guard occurredAt <= receivedAt.addingTimeInterval(1) else {
            throw NormalizedAgentEventError.invalidTime
        }
        self.source = source
        self.sessionID = sessionID
        self.turnID = normalizedTurnID
        self.sourceEvent = sourceEvent
        self.eventKeyComponent = eventKeyComponent
        self.status = status
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.closesRun = closesRun
        self.startsRun = startsRun
        self.projectPath = projectPath
        self.title = title
        self.lastMessage = lastMessage
    }
}

public struct CodexNotifyDTO: Decodable, Sendable {
    public let type: String
    public let threadID: String
    public let turnID: String
    public let cwd: String?
    public let inputMessages: [String]?
    public let lastAssistantMessage: String?

    enum CodingKeys: String, CodingKey {
        case type
        case threadID = "thread-id"
        case turnID = "turn-id"
        case cwd
        case inputMessages = "input-messages"
        case lastAssistantMessage = "last-assistant-message"
    }
}

public struct ClaudeHookDTO: Decodable, Sendable {
    public let sessionID: String
    public let promptID: String?
    public let cwd: String?
    public let hookEventName: String?
    public let lastAssistantMessage: String?
    public let notificationType: String?
    public let taskID: String?
    public let error: String?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case promptID = "prompt_id"
        case cwd
        case hookEventName = "hook_event_name"
        case lastAssistantMessage = "last_assistant_message"
        case notificationType = "notification_type"
        case taskID = "task_id"
        case error
        case message
    }
}

public enum AgentEventNormalizer {
    public static func codex(
        _ dto: CodexNotifyDTO,
        receivedAt: Date,
        privacy: AgentPrivacyPolicy
    ) throws -> NormalizedAgentEvent {
        guard dto.type == "agent-turn-complete" else {
            throw NormalizedAgentEventError.invalidSourceEvent
        }
        return try NormalizedAgentEvent(
            source: .codex,
            sessionID: dto.threadID,
            turnID: dto.turnID,
            sourceEvent: dto.type,
            eventKeyComponent: "agent-turn-complete",
            status: .responded,
            occurredAt: receivedAt,
            receivedAt: receivedAt,
            closesRun: true,
            projectPath: privacy.storeProjectPath
                ? sanitizePath(dto.cwd) : nil,
            title: privacy.storeAgentTitle
                ? sanitize(dto.inputMessages?.first, limit: 200) : nil,
            lastMessage: privacy.storeLastMessage
                ? sanitize(dto.lastAssistantMessage, limit: 1_000) : nil
        )
    }

    public static func claude(
        _ dto: ClaudeHookDTO,
        eventHint: String,
        receivedAt: Date,
        privacy: AgentPrivacyPolicy,
        fallbackTurnID: @autoclosure () -> String
    ) throws -> NormalizedAgentEvent {
        let turnID: String?
        let status: AgentStatus
        let component: String
        let closes: Bool
        let starts: Bool
        switch eventHint {
        case "UserPromptSubmit":
            turnID = dto.promptID?.nilIfBlank ?? fallbackTurnID()
            status = .running
            component = "start"
            closes = false
            starts = true
        case "Notification":
            let allowed = [
                "permission_prompt",
                "elicitation_dialog",
                "agent_needs_input",
            ]
            guard let type = dto.notificationType,
                  allowed.contains(type) else {
                throw NormalizedAgentEventError.invalidSourceEvent
            }
            turnID = dto.promptID?.nilIfBlank
            status = .attentionRequired
            component = "notification:\(type):\(digest(dto.message ?? ""))"
            closes = false
            starts = false
        case "TaskCompleted":
            turnID = dto.promptID?.nilIfBlank
            status = .completed
            component = "task:\(dto.taskID?.nilIfBlank ?? digest(dto.message ?? ""))"
            closes = false
            starts = false
        case "Stop":
            turnID = dto.promptID?.nilIfBlank
            status = .responded
            component = "stop"
            closes = true
            starts = false
        case "StopFailure":
            turnID = dto.promptID?.nilIfBlank
            status = .failed
            component = "failure:\(digest(dto.error ?? ""))"
            closes = true
            starts = false
        default:
            throw NormalizedAgentEventError.invalidSourceEvent
        }
        return try NormalizedAgentEvent(
            source: .claude,
            sessionID: dto.sessionID,
            turnID: turnID,
            sourceEvent: eventHint,
            eventKeyComponent: component,
            status: status,
            occurredAt: receivedAt,
            receivedAt: receivedAt,
            closesRun: closes,
            startsRun: starts,
            projectPath: privacy.storeProjectPath
                ? sanitizePath(dto.cwd) : nil,
            title: nil,
            lastMessage: privacy.storeLastMessage
                ? sanitize(dto.lastAssistantMessage, limit: 1_000) : nil
        )
    }

    private static func sanitize(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value.unicodeScalars
            .filter {
                !CharacterSet.controlCharacters.contains($0)
                    || $0 == "\n"
            }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(limit))
    }

    private static func sanitizePath(_ value: String?) -> String? {
        guard let value = sanitize(value, limit: 1_024) else { return nil }
        return NSString(string: value).standardizingPath
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
