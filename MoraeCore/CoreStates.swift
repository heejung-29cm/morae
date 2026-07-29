import Foundation

public struct AppError: Error, Equatable, Codable, Sendable, LocalizedError {
    public let code: String
    public let userMessage: String
    public let recovery: String?

    public init(code: String, userMessage: String, recovery: String? = nil) {
        self.code = code
        self.userMessage = userMessage
        self.recovery = recovery
    }

    public var errorDescription: String? {
        userMessage
    }

    public var recoverySuggestion: String? {
        recovery
    }
}

public enum TodoStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
}

public enum TodoPriority: Int, Codable, CaseIterable, Sendable {
    case normal = 0
    case important = 1
}

public enum BriefingStatus: String, Codable, CaseIterable, Sendable {
    case running
    case succeeded
    case failed
}

public enum AgentSource: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
}

public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case running
    case attentionRequired = "attention_required"
    case responded
    case completed
    case failed
    case cancelled

    public var rank: Int {
        switch self {
        case .failed: 50
        case .completed: 40
        case .responded: 30
        case .attentionRequired: 20
        case .running: 10
        case .cancelled: 0
        }
    }
}

public enum AgentClosureReason: String, Codable, CaseIterable, Sendable {
    case terminalEvent = "terminal_event"
    case superseded
}

public enum BriefingErrorCode: String, Codable, CaseIterable, Sendable {
    case noEnabledFeeds = "no_enabled_feeds"
    case noCandidates = "no_candidates"
    case feedUnavailable = "feed_unavailable"
    case persistenceFailed = "persistence_failed"
}

public enum AgentIngressErrorCode: String, Codable, CaseIterable, Sendable {
    case unsupportedTransport = "unsupported_transport"
    case payloadTooLarge = "payload_too_large"
    case invalidPayload = "invalid_payload"
    case unsupportedEvent = "unsupported_event"
    case peerRejected = "peer_rejected"
    case persistenceFailed = "persistence_failed"
}
