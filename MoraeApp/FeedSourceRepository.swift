import Foundation
import GRDB
import MoraeCore

protocol FeedSourceRepository: Sendable {
    func seedDefaults(_ sources: [FeedSource]) async throws
    func allSources() async throws -> [FeedSource]
    func enabledSources() async throws -> [FeedSource]
    func add(_ source: FeedSource) async throws
    func setEnabled(id: UUID, enabled: Bool, at: Date) async throws
    func deleteCustom(id: UUID) async throws
    func markChecked(id: UUID, at: Date) async throws
}

enum FeedSourceMappingError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidURL(String)
    case duplicateURL
    case officialSourceCannotBeDeleted
}

enum DefaultFeedError: Error, Equatable, Sendable {
    case resourceMissing
    case invalidID(String)
    case invalidURL(String)
    case insecureURL(String)
    case invalidSelectionWeight(Int)
}

struct DefaultFeedDefinition: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let feedURL: String
    let isOfficial: Bool
    let selectionWeight: Int?

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
        let selectionWeight = selectionWeight ?? 0
        guard (0...100).contains(selectionWeight) else {
            throw DefaultFeedError.invalidSelectionWeight(selectionWeight)
        }
        return FeedSource(
            id: id,
            name: name,
            feedURL: url,
            isOfficial: isOfficial,
            selectionWeight: selectionWeight,
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
    let selectionWeight: Int
    let isEnabled: Bool
    let lastCheckedAtMs: Int64?
    let createdAtMs: Int64
    let updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case feedURL = "feed_url"
        case isOfficial = "is_official"
        case selectionWeight = "selection_weight"
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
        selectionWeight = source.selectionWeight
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
            selectionWeight: selectionWeight,
            isEnabled: isEnabled,
            lastCheckedAt: lastCheckedAtMs.map(Date.init(unixMilliseconds:)),
            createdAt: Date(unixMilliseconds: createdAtMs),
            updatedAt: Date(unixMilliseconds: updatedAtMs)
        )
    }
}

final class GRDBFeedSourceRepository: FeedSourceRepository, @unchecked Sendable {
    private static let seedKey = "default_feeds_seeded_v3"
    private static let retiredDefaultIDs = [
        "8b064c57-30c5-4b87-863f-edb32940237a",
        "97014c67-3ffe-4701-a792-c07dccbc0c3c",
        "8fa75519-5664-45ca-a687-5be871bb5f28",
        "b487dcfb-a5cd-4400-bf33-6da825f4db06",
        "7065e141-9c37-456c-84f5-a7d30a59bdcb",
        "8c0c262f-f382-4fe4-a2a4-38c486b92055",
        "50ee594a-9d5d-413e-88c8-25756a295def",
    ]
    private static let retiredDefaultFeedURLs = [
        "https://developer.mozilla.org/en-US/blog/rss.xml",
        "https://web.dev/static/blog/feed.xml",
        "https://developer.chrome.com/static/blog/feed.xml",
        "https://react.dev/rss.xml",
        "https://fenews.substack.com/feed",
        "https://frontendfoc.us/rss/",
        "https://javascriptweekly.com/rss/",
    ]
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

    func allSources() async throws -> [FeedSource] {
        try await writer.read { database in
            try FeedSourceRecord.fetchAll(
                database,
                sql: """
                    SELECT * FROM feed_sources
                    ORDER BY is_official DESC, created_at_ms ASC, id ASC
                    """
            )
            .map { try $0.domain() }
        }
    }

    func add(_ source: FeedSource) async throws {
        do {
            try await writer.write { database in
                try FeedSourceRecord(source: source).insert(database)
            }
        } catch let error as DatabaseError
            where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw FeedSourceMappingError.duplicateURL
        }
    }

    func setEnabled(
        id: UUID,
        enabled: Bool,
        at date: Date
    ) async throws {
        try await writer.write { database in
            try database.execute(
                sql: """
                    UPDATE feed_sources
                    SET is_enabled = ?, updated_at_ms = ?
                    WHERE id = ?
                    """,
                arguments: [
                    enabled,
                    date.unixMilliseconds,
                    id.uuidString.lowercased(),
                ]
            )
        }
    }

    func deleteCustom(id: UUID) async throws {
        try await writer.write { database in
            let isOfficial = try Bool.fetchOne(
                database,
                sql: "SELECT is_official FROM feed_sources WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            )
            guard isOfficial != true else {
                throw FeedSourceMappingError.officialSourceCannotBeDeleted
            }
            try database.execute(
                sql: "DELETE FROM feed_sources WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            )
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
        try database.execute(
            sql: """
                UPDATE feed_sources
                SET is_enabled = 0,
                    updated_at_ms = ?
                WHERE id IN (?, ?, ?, ?, ?, ?, ?)
                   OR feed_url IN (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                sources.first?.updatedAt.unixMilliseconds
                    ?? Date().unixMilliseconds,
                retiredDefaultIDs[0],
                retiredDefaultIDs[1],
                retiredDefaultIDs[2],
                retiredDefaultIDs[3],
                retiredDefaultIDs[4],
                retiredDefaultIDs[5],
                retiredDefaultIDs[6],
                retiredDefaultFeedURLs[0],
                retiredDefaultFeedURLs[1],
                retiredDefaultFeedURLs[2],
                retiredDefaultFeedURLs[3],
                retiredDefaultFeedURLs[4],
                retiredDefaultFeedURLs[5],
                retiredDefaultFeedURLs[6],
            ]
        )
        for source in sources {
            let record = FeedSourceRecord(source: source)
            try record.insert(database, onConflict: .ignore)
            try database.execute(
                sql: """
                    UPDATE feed_sources
                    SET name = ?,
                        is_official = ?,
                        selection_weight = ?,
                        is_enabled = 1,
                        updated_at_ms = ?
                    WHERE feed_url = ?
                    """,
                arguments: [
                    source.name,
                    source.isOfficial,
                    source.selectionWeight,
                    source.updatedAt.unixMilliseconds,
                    source.feedURL.absoluteString,
                ]
            )
        }
        try database.execute(
            sql: "INSERT INTO app_metadata (key, value) VALUES (?, ?)",
            arguments: [seedKey, "1"]
        )
    }
}
