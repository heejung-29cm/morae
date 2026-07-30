import Foundation
import GRDB
import MoraeCore

protocol FeedSourceRepository: Sendable {
    func seedDefaults(_ sources: [FeedSource]) async throws
    func enabledSources() async throws -> [FeedSource]
    func markChecked(id: UUID, at: Date) async throws
}

enum FeedSourceMappingError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidURL(String)
}

enum DefaultFeedError: Error, Equatable, Sendable {
    case resourceMissing
    case invalidID(String)
    case invalidURL(String)
    case insecureURL(String)
}

struct DefaultFeedDefinition: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let feedURL: String
    let isOfficial: Bool

    func source(at date: Date) throws -> FeedSource {
        guard let id = UUID(uuidString: id) else {
            throw DefaultFeedError.invalidID(self.id)
        }
        guard let url = URL(string: feedURL) else {
            throw DefaultFeedError.invalidURL(feedURL)
        }
        guard url.scheme?.lowercased() == "https" else {
            throw DefaultFeedError.insecureURL(feedURL)
        }
        return FeedSource(
            id: id,
            name: name,
            feedURL: url,
            isOfficial: isOfficial,
            createdAt: date,
            updatedAt: date
        )
    }
}

enum DefaultFeedLoader {
    static func load(
        bundle: Bundle = .main,
        at date: Date
    ) throws -> [FeedSource] {
        guard let url = bundle.url(
            forResource: "DefaultFeeds",
            withExtension: "json"
        ) else {
            throw DefaultFeedError.resourceMissing
        }
        return try decode(data: Data(contentsOf: url), at: date)
    }

    static func decode(data: Data, at date: Date) throws -> [FeedSource] {
        try JSONDecoder()
            .decode([DefaultFeedDefinition].self, from: data)
            .map { try $0.source(at: date) }
    }
}

struct FeedSourceRecord:
    Codable,
    FetchableRecord,
    PersistableRecord,
    TableRecord,
    Sendable
{
    static let databaseTableName = "feed_sources"

    let id: String
    let name: String
    let feedURL: String
    let isOfficial: Bool
    let isEnabled: Bool
    let lastCheckedAtMs: Int64?
    let createdAtMs: Int64
    let updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case feedURL = "feed_url"
        case isOfficial = "is_official"
        case isEnabled = "is_enabled"
        case lastCheckedAtMs = "last_checked_at_ms"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    init(source: FeedSource) {
        id = source.id.uuidString.lowercased()
        name = source.name
        feedURL = source.feedURL.absoluteString
        isOfficial = source.isOfficial
        isEnabled = source.isEnabled
        lastCheckedAtMs = source.lastCheckedAt?.unixMilliseconds
        createdAtMs = source.createdAt.unixMilliseconds
        updatedAtMs = source.updatedAt.unixMilliseconds
    }

    func domain() throws -> FeedSource {
        guard let id = UUID(uuidString: id) else {
            throw FeedSourceMappingError.invalidID(self.id)
        }
        guard let feedURL = URL(string: feedURL) else {
            throw FeedSourceMappingError.invalidURL(self.feedURL)
        }
        return FeedSource(
            id: id,
            name: name,
            feedURL: feedURL,
            isOfficial: isOfficial,
            isEnabled: isEnabled,
            lastCheckedAt: lastCheckedAtMs.map(Date.init(unixMilliseconds:)),
            createdAt: Date(unixMilliseconds: createdAtMs),
            updatedAt: Date(unixMilliseconds: updatedAtMs)
        )
    }
}

final class GRDBFeedSourceRepository: FeedSourceRepository, @unchecked Sendable {
    private static let seedKey = "default_feeds_seeded"
    private let writer: any DatabaseWriter

    init(database: AppDatabase) {
        writer = database.writer
    }

    func seedDefaults(_ sources: [FeedSource]) async throws {
        try await writer.write { database in
            try Self.seedDefaults(sources, in: database)
        }
    }

    func seedDefaultsSynchronously(_ sources: [FeedSource]) throws {
        try writer.writeWithoutTransaction { database in
            try database.inTransaction {
                try Self.seedDefaults(sources, in: database)
                return .commit
            }
        }
    }

    func enabledSources() async throws -> [FeedSource] {
        try await writer.read { database in
            try FeedSourceRecord.fetchAll(
                database,
                sql: """
                    SELECT *
                    FROM feed_sources
                    WHERE is_enabled = 1
                    ORDER BY created_at_ms ASC, id ASC
                    """
            )
            .map { try $0.domain() }
        }
    }

    func markChecked(id: UUID, at date: Date) async throws {
        try await writer.write { database in
            try database.execute(
                sql: """
                    UPDATE feed_sources
                    SET last_checked_at_ms = ?, updated_at_ms = ?
                    WHERE id = ?
                    """,
                arguments: [
                    date.unixMilliseconds,
                    date.unixMilliseconds,
                    id.uuidString.lowercased(),
                ]
            )
        }
    }

    private static func seedDefaults(
        _ sources: [FeedSource],
        in database: Database
    ) throws {
        let seeded = try String.fetchOne(
            database,
            sql: "SELECT value FROM app_metadata WHERE key = ?",
            arguments: [seedKey]
        )
        guard seeded == nil else {
            return
        }
        for source in sources {
            try FeedSourceRecord(source: source).insert(database)
        }
        try database.execute(
            sql: "INSERT INTO app_metadata (key, value) VALUES (?, ?)",
            arguments: [seedKey, "1"]
        )
    }
}
