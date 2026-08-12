import Foundation
import GRDB
import MoraeCore

struct StoredBriefing: Equatable, Sendable {
    let run: BriefingRun
    let article: Article?
}

protocol BriefingRepository: Sendable {
    func createRunning(day: LocalDay, at: Date) async throws -> BriefingRun
    func finish(
        run: BriefingRun,
        article: Article?
    ) async throws -> StoredBriefing
    func latest(day: LocalDay) async throws -> StoredBriefing?
}

enum BriefingRepositoryError: Error, Equatable, Sendable {
    case invalidTransition
    case runNotFound(BriefingRunID)
}

enum BriefingMappingError: Error, Equatable, Sendable {
    case invalidID(String)
    case invalidDay(String)
    case invalidStatus(String)
    case invalidArticleID(String)
    case invalidErrorCode(String)
}

struct BriefingRunRecord:
    Codable,
    FetchableRecord,
    PersistableRecord,
    TableRecord,
    Sendable
{
    static let databaseTableName = "briefing_runs"

    let id: String
    let briefingDay: String
    var status: String
    var selectedArticleID: String?
    let triggeredAtMs: Int64
    var finishedAtMs: Int64?
    var errorCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case briefingDay = "briefing_day"
        case status
        case selectedArticleID = "selected_article_id"
        case triggeredAtMs = "triggered_at_ms"
        case finishedAtMs = "finished_at_ms"
        case errorCode = "error_code"
    }

    init(run: BriefingRun) {
        id = run.id.storageValue
        briefingDay = run.day.rawValue
        status = run.status.rawValue
        selectedArticleID = run.selectedArticleID?.storageValue
        triggeredAtMs = run.triggeredAt.unixMilliseconds
        finishedAtMs = run.finishedAt?.unixMilliseconds
        errorCode = run.errorCode?.rawValue
    }

    func domain() throws -> BriefingRun {
        guard let id = UUID(uuidString: id) else {
            throw BriefingMappingError.invalidID(self.id)
        }
        let day: LocalDay
        do {
            day = try LocalDay(rawValue: briefingDay)
        } catch {
            throw BriefingMappingError.invalidDay(briefingDay)
        }
        guard let status = BriefingStatus(rawValue: status) else {
            throw BriefingMappingError.invalidStatus(self.status)
        }
        let selectedArticleID: ArticleID?
        if let value = self.selectedArticleID {
            guard let id = UUID(uuidString: value) else {
                throw BriefingMappingError.invalidArticleID(value)
            }
            selectedArticleID = ArticleID(rawValue: id)
        } else {
            selectedArticleID = nil
        }
        let errorCode: BriefingErrorCode?
        if let value = self.errorCode {
            guard let code = BriefingErrorCode(rawValue: value) else {
                throw BriefingMappingError.invalidErrorCode(value)
            }
            errorCode = code
        } else {
            errorCode = nil
        }
        return BriefingRun(
            id: BriefingRunID(rawValue: id),
            day: day,
            status: status,
            selectedArticleID: selectedArticleID,
            triggeredAt: Date(unixMilliseconds: triggeredAtMs),
            finishedAt: finishedAtMs.map(Date.init(unixMilliseconds:)),
            errorCode: errorCode
        )
    }
}

final class GRDBBriefingRepository:
    BriefingRepository,
    @unchecked Sendable
{
    private let writer: any DatabaseWriter
    private let uuidGenerator: any UUIDGenerating
    private let canonicalizer: URLCanonicalizer

    init(
        database: AppDatabase,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator(),
        canonicalizer: URLCanonicalizer = URLCanonicalizer()
    ) {
        writer = database.writer
        self.uuidGenerator = uuidGenerator
        self.canonicalizer = canonicalizer
    }

    func createRunning(
        day: LocalDay,
        at date: Date
    ) async throws -> BriefingRun {
        let run = BriefingRun(
            id: BriefingRunID(rawValue: uuidGenerator.next()),
            day: day,
            status: .running,
            triggeredAt: date
        )
        try await writer.write { database in
            try BriefingRunRecord(run: run).insert(database)
        }
        return run
    }

    func finish(
        run: BriefingRun,
        article: Article?
    ) async throws -> StoredBriefing {
        guard run.status != .running,
              run.finishedAt != nil,
              (run.status == .succeeded) == (article != nil),
              (run.status == .failed) == (run.errorCode != nil) else {
            throw BriefingRepositoryError.invalidTransition
        }

        let canonicalURL = try article.map {
            try canonicalizer.canonicalize($0.canonicalURL)
        }
        return try await writer.write { database in
            let storedArticle: Article?
            if let article, let canonicalURL {
                try Self.upsert(
                    ArticleRecord(
                        article: article,
                        canonicalURL: canonicalURL
                    ),
                    in: database
                )
                storedArticle = try ArticleRecord.fetchOne(
                    database,
                    sql: "SELECT * FROM articles WHERE canonical_url = ?",
                    arguments: [canonicalURL.absoluteString]
                )?
                .domain()
            } else {
                storedArticle = nil
            }

            try database.execute(
                sql: """
                    UPDATE briefing_runs
                    SET status = ?,
                        selected_article_id = ?,
                        finished_at_ms = ?,
                        error_code = ?
                    WHERE id = ? AND status = 'running'
                    """,
                arguments: [
                    run.status.rawValue,
                    storedArticle?.id.storageValue,
                    run.finishedAt?.unixMilliseconds,
                    run.errorCode?.rawValue,
                    run.id.storageValue,
                ]
            )
            guard database.changesCount == 1,
                  let storedRun = try BriefingRunRecord.fetchOne(
                    database,
                    key: run.id.storageValue
                  )?.domain() else {
                throw BriefingRepositoryError.runNotFound(run.id)
            }
            return StoredBriefing(
                run: storedRun,
                article: storedArticle
            )
        }
    }

    func latest(day: LocalDay) async throws -> StoredBriefing? {
        try await writer.read { database in
            guard let run = try BriefingRunRecord.fetchOne(
                database,
                sql: """
                    SELECT *
                    FROM briefing_runs
                    WHERE briefing_day = ?
                    ORDER BY triggered_at_ms DESC, id DESC
                    LIMIT 1
                    """,
                arguments: [day.rawValue]
            )?
            .domain() else {
                return nil
            }
            let article = try run.selectedArticleID.flatMap { id in
                try ArticleRecord.fetchOne(
                    database,
                    key: id.storageValue
                )?
                .domain()
            }
            return StoredBriefing(run: run, article: article)
        }
    }

    private static func upsert(
        _ record: ArticleRecord,
        in database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO articles (
                    id, canonical_url, title, source_name, source_url,
                    published_at_ms, is_read, is_liked,
                    created_at_ms, updated_at_ms, feedback, topic
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(canonical_url) DO UPDATE SET
                    title = excluded.title,
                    source_name = excluded.source_name,
                    source_url = excluded.source_url,
                    published_at_ms = excluded.published_at_ms,
                    topic = excluded.topic,
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
                record.feedback,
                record.topic,
            ]
        )
    }
}
