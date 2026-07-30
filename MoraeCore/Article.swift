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
