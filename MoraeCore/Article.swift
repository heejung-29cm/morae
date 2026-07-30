import Foundation

public struct FeedSource: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let feedURL: URL
    public let isOfficial: Bool
    public let isEnabled: Bool
    public let lastCheckedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        name: String,
        feedURL: URL,
        isOfficial: Bool,
        isEnabled: Bool = true,
        lastCheckedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.feedURL = feedURL
        self.isOfficial = isOfficial
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

    public init(
        sourceID: UUID,
        sourceName: String,
        sourceURL: URL,
        articleURL: URL,
        title: String,
        publishedAt: Date?,
        isOfficialSource: Bool
    ) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.articleURL = articleURL
        self.title = title
        self.publishedAt = publishedAt
        self.isOfficialSource = isOfficialSource
    }
}
