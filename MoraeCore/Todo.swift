import Foundation

public enum TodoValidationError: Error, Equatable, Sendable {
    case emptyTitle
    case titleTooLong
    case invalidEstimatedMinutes
    case invalidRelatedURL
    case invalidCompletionState
}

public struct JiraTodoMetadata: Equatable, Sendable {
    public let issueID: String
    public let issueKey: String
    public let statusCategory: String
    public let statusName: String
    public let startDay: LocalDay?
    public let dueDay: LocalDay?
    public let syncedAt: Date

    public init(
        issueID: String,
        issueKey: String,
        statusCategory: String,
        statusName: String,
        startDay: LocalDay?,
        dueDay: LocalDay?,
        syncedAt: Date
    ) {
        self.issueID = issueID
        self.issueKey = issueKey
        self.statusCategory = statusCategory
        self.statusName = statusName
        self.startDay = startDay
        self.dueDay = dueDay
        self.syncedAt = syncedAt
    }
}

public enum TodoOrigin: Equatable, Sendable {
    case manual
    case carryOver(sourceID: TodoID)
    case jira(JiraTodoMetadata)

    public var isJira: Bool {
        if case .jira = self {
            return true
        }
        return false
    }
}

public struct TodoItem: Identifiable, Equatable, Sendable {
    public let id: TodoID
    public var title: String
    public var day: LocalDay
    public var status: TodoStatus
    public var priority: TodoPriority
    public var sortOrder: Int
    public var estimatedMinutes: Int?
    public var relatedURL: URL?
    public var projectPath: String?
    public var origin: TodoOrigin
    public var completedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: TodoID,
        title: String,
        day: LocalDay,
        status: TodoStatus,
        priority: TodoPriority,
        sortOrder: Int,
        estimatedMinutes: Int? = nil,
        relatedURL: URL? = nil,
        projectPath: String? = nil,
        origin: TodoOrigin = .manual,
        completedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw TodoValidationError.emptyTitle
        }
        guard normalizedTitle.count <= 200 else {
            throw TodoValidationError.titleTooLong
        }
        if let estimatedMinutes, !(1...1_440).contains(estimatedMinutes) {
            throw TodoValidationError.invalidEstimatedMinutes
        }
        if let relatedURL {
            let allowedSchemes = Set(["https", "http", "file"])
            guard let scheme = relatedURL.scheme?.lowercased(),
                  allowedSchemes.contains(scheme) else {
                throw TodoValidationError.invalidRelatedURL
            }
        }
        guard (status == .completed && completedAt != nil)
                || (status == .pending && completedAt == nil) else {
            throw TodoValidationError.invalidCompletionState
        }

        self.id = id
        self.title = normalizedTitle
        self.day = day
        self.status = status
        self.priority = priority
        self.sortOrder = sortOrder
        self.estimatedMinutes = estimatedMinutes
        self.relatedURL = relatedURL
        self.projectPath = projectPath
        self.origin = origin
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
