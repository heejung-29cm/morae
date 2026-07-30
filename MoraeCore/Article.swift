import Foundation

public struct FeedSource: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let feedURL: URL
    public let isOfficial: Bool
    public let selectionWeight: Int
    public let isEnabled: Bool
    public let lastCheckedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        name: String,
        feedURL: URL,
        isOfficial: Bool,
        selectionWeight: Int = 0,
        isEnabled: Bool = true,
        lastCheckedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.feedURL = feedURL
        self.isOfficial = isOfficial
        self.selectionWeight = selectionWeight
        self.isEnabled = isEnabled
        self.lastCheckedAt = lastCheckedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FeedCandidate: Hashable, Sendable {
    public let sourceID: UUID
    public let sourceName: String
    public let sourceURL: URL
    public let articleURL: URL
    public let title: String
    public let publishedAt: Date?
    public let isOfficialSource: Bool
    public let selectionWeight: Int

    public init(
        sourceID: UUID,
        sourceName: String,
        sourceURL: URL,
        articleURL: URL,
        title: String,
        publishedAt: Date?,
        isOfficialSource: Bool,
        selectionWeight: Int = 0
    ) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.articleURL = articleURL
        self.title = title
        self.publishedAt = publishedAt
        self.isOfficialSource = isOfficialSource
        self.selectionWeight = selectionWeight
    }
}

public struct Article: Identifiable, Equatable, Sendable {
    public let id: ArticleID
    public let canonicalURL: URL
    public let title: String
    public let sourceName: String
    public let sourceURL: URL?
    public let publishedAt: Date?
    public var isRead: Bool
    public var isLiked: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ArticleID,
        canonicalURL: URL,
        title: String,
        sourceName: String,
        sourceURL: URL?,
        publishedAt: Date?,
        isRead: Bool,
        isLiked: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.canonicalURL = canonicalURL
        self.title = title
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.publishedAt = publishedAt
        self.isRead = isRead
        self.isLiked = isLiked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BriefingRun: Identifiable, Equatable, Sendable {
    public let id: BriefingRunID
    public let day: LocalDay
    public var status: BriefingStatus
    public var selectedArticleID: ArticleID?
    public let triggeredAt: Date
    public var finishedAt: Date?
    public var errorCode: BriefingErrorCode?

    public init(
        id: BriefingRunID,
        day: LocalDay,
        status: BriefingStatus,
        selectedArticleID: ArticleID? = nil,
        triggeredAt: Date,
        finishedAt: Date? = nil,
        errorCode: BriefingErrorCode? = nil
    ) {
        self.id = id
        self.day = day
        self.status = status
        self.selectedArticleID = selectedArticleID
        self.triggeredAt = triggeredAt
        self.finishedAt = finishedAt
        self.errorCode = errorCode
    }
}
