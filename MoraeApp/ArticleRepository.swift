import Foundation
import GRDB
import MoraeCore

protocol ArticleRepository: Sendable {
    func previouslyRecommendedURLs() async throws -> Set<URL>
    func readURLs() async throws -> Set<URL>
    func upsert(_ article: Article) async throws
    func find(canonicalURL: URL) async throws -> Article?
    func setRead(
        canonicalURL: URL,
        isRead: Bool,
        at: Date
    ) async throws
    func setLiked(
        canonicalURL: URL,
        isLiked: Bool,
        at: Date
    ) async throws
}

enum ArticleMappingError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidCanonicalURL(String)
    case invalidSourceURL(String)
}

struct ArticleRecord:
    Codable,
    FetchableRecord,
    PersistableRecord,
    TableRecord,
    Sendable
{
    static let databaseTableName = "articles"

    let id: String
    let canonicalURL: String
    let title: String
    let sourceName: String
    let sourceURL: String?
    let publishedAtMs: Int64?
    let isRead: Bool
    let isLiked: Bool
    let createdAtMs: Int64
    let updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case canonicalURL = "canonical_url"
        case title
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case publishedAtMs = "published_at_ms"
        case isRead = "is_read"
        case isLiked = "is_liked"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    init(article: Article, canonicalURL: URL) {
        id = article.id.storageValue
        self.canonicalURL = canonicalURL.absoluteString
        title = article.title
        sourceName = article.sourceName
        sourceURL = article.sourceURL?.absoluteString
        publishedAtMs = article.publishedAt?.unixMilliseconds
        isRead = article.isRead
        isLiked = article.isLiked
        createdAtMs = article.createdAt.unixMilliseconds
        updatedAtMs = article.updatedAt.unixMilliseconds
    }

    func domain() throws -> Article {
        guard let id = UUID(uuidString: id) else {
            throw ArticleMappingError.invalidID(self.id)
        }
        guard let canonicalURL = URL(string: canonicalURL) else {
            throw ArticleMappingError.invalidCanonicalURL(self.canonicalURL)
        }
        let parsedSourceURL: URL?
        if let value = self.sourceURL {
            guard let parsed = URL(string: value) else {
                throw ArticleMappingError.invalidSourceURL(value)
            }
            parsedSourceURL = parsed
        } else {
            parsedSourceURL = nil
        }
        return Article(
            id: ArticleID(rawValue: id),
            canonicalURL: canonicalURL,
            title: title,
            sourceName: sourceName,
            sourceURL: parsedSourceURL,
            publishedAt: publishedAtMs.map(Date.init(unixMilliseconds:)),
            isRead: isRead,
            isLiked: isLiked,
            createdAt: Date(unixMilliseconds: createdAtMs),
            updatedAt: Date(unixMilliseconds: updatedAtMs)
        )
    }
}

final class GRDBArticleRepository: ArticleRepository, @unchecked Sendable {
    private let writer: any DatabaseWriter
    private let clock: any Clock
    private let canonicalizer: URLCanonicalizer

    init(
        database: AppDatabase,
        clock: any Clock,
        canonicalizer: URLCanonicalizer = URLCanonicalizer()
    ) {
        writer = database.writer
        self.clock = clock
        self.canonicalizer = canonicalizer
    }

    func previouslyRecommendedURLs() async throws -> Set<URL> {
        let cutoff = clock.now().addingTimeInterval(-90 * 86_400)
        return try await writer.read { database in
            let values = try String.fetchAll(
                database,
                sql: """
                    SELECT DISTINCT articles.canonical_url
                    FROM briefing_runs
                    JOIN articles
                      ON articles.id = briefing_runs.selected_article_id
                    WHERE briefing_runs.status = 'succeeded'
                      AND briefing_runs.triggered_at_ms >= ?
                    """,
                arguments: [cutoff.unixMilliseconds]
            )
            return Set(values.compactMap(URL.init(string:)))
        }
    }

    func readURLs() async throws -> Set<URL> {
        try await writer.read { database in
            Set(
                try String.fetchAll(
                    database,
                    sql: """
                        SELECT canonical_url
                        FROM articles
                        WHERE is_read = 1
                        """
                )
                .compactMap(URL.init(string:))
            )
        }
    }

    func upsert(_ article: Article) async throws {
        let canonicalURL = try canonicalizer.canonicalize(
            article.canonicalURL
        )
        let record = ArticleRecord(
            article: article,
            canonicalURL: canonicalURL
        )
        try await writer.write { database in
            try database.execute(
                sql: """
                    INSERT INTO articles (
                        id, canonical_url, title, source_name, source_url,
                        published_at_ms, is_read, is_liked,
                        created_at_ms, updated_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(canonical_url) DO UPDATE SET
                        title = excluded.title,
                        source_name = excluded.source_name,
                        source_url = excluded.source_url,
                        published_at_ms = excluded.published_at_ms,
                        is_read = excluded.is_read,
                        is_liked = excluded.is_liked,
                        updated_at_ms = excluded.updated_at_ms
                    """,
                arguments: [
                    record.id,
                    record.canonicalURL,
                    record.title,
                    record.sourceName,
                    record.sourceURL,
                    record.publishedAtMs,
                    record.isRead,
                    record.isLiked,
                    record.createdAtMs,
                    record.updatedAtMs,
                ]
            )
        }
    }

    func find(canonicalURL: URL) async throws -> Article? {
        let canonicalURL = try canonicalizer.canonicalize(canonicalURL)
        return try await writer.read { database in
            try ArticleRecord.fetchOne(
                database,
                sql: "SELECT * FROM articles WHERE canonical_url = ?",
                arguments: [canonicalURL.absoluteString]
            )?
            .domain()
        }
    }

    func setRead(
        canonicalURL: URL,
        isRead: Bool,
        at date: Date
    ) async throws {
        try await updateFlag(
            column: "is_read",
            value: isRead,
            canonicalURL: canonicalURL,
            at: date
        )
    }

    func setLiked(
        canonicalURL: URL,
        isLiked: Bool,
        at date: Date
    ) async throws {
        try await updateFlag(
            column: "is_liked",
            value: isLiked,
            canonicalURL: canonicalURL,
            at: date
        )
    }

    private func updateFlag(
        column: String,
        value: Bool,
        canonicalURL: URL,
        at date: Date
    ) async throws {
        precondition(["is_read", "is_liked"].contains(column))
        let canonicalURL = try canonicalizer.canonicalize(canonicalURL)
        try await writer.write { database in
            try database.execute(
                literal: """
                    UPDATE articles
                    SET \(sql: column) = \(value),
                        updated_at_ms = \(date.unixMilliseconds)
                    WHERE canonical_url = \(canonicalURL.absoluteString)
                    """
            )
        }
    }
}
