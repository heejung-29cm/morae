import GRDB
import MoraeCore
import XCTest
@testable import MoraeApp

final class ArticleRepositoryTests: XCTestCase {
    func testUpsertUsesCanonicalURLAndRoundTripsMetadata() async throws {
        let database = try AppDatabase.inMemory()
        let clock = FixedClock(instant: Date(unixMilliseconds: 2_000_000_000_000))
        let repository = GRDBArticleRepository(
            database: database,
            clock: clock
        )
        let original = article(
            id: "20000000-0000-0000-0000-000000000001",
            url: "https://EXAMPLE.com:443/post?utm_source=feed&b=2&a=1#top",
            title: "Original",
            isRead: false,
            isLiked: false
        )
        let replacement = article(
            id: "20000000-0000-0000-0000-000000000002",
            url: "https://example.com/post?a=1&b=2",
            title: "Updated",
            isRead: true,
            isLiked: true
        )

        try await repository.upsert(original)
        try await repository.upsert(replacement)

        let found = try await repository.find(canonicalURL: original.canonicalURL)
        let stored = try XCTUnwrap(found)
        XCTAssertEqual(stored.id, original.id)
        XCTAssertEqual(
            stored.canonicalURL.absoluteString,
            "https://example.com/post?a=1&b=2"
        )
        XCTAssertEqual(stored.title, "Updated")
        XCTAssertEqual(stored.sourceName, "Morae Fixture")
        XCTAssertEqual(
            stored.sourceURL,
            URL(string: "https://source.invalid/feed.xml")
        )
        XCTAssertEqual(stored.publishedAt, replacement.publishedAt)
        XCTAssertTrue(stored.isRead)
        XCTAssertTrue(stored.isLiked)

        let count = try database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM articles")
        }
        XCTAssertEqual(count, 1)
    }

    func testReadAndLikedFlagsPersist() async throws {
        let database = try AppDatabase.inMemory()
        let now = Date(unixMilliseconds: 2_000_000_000_000)
        let repository = GRDBArticleRepository(
            database: database,
            clock: FixedClock(instant: now)
        )
        let item = article(
            id: "20000000-0000-0000-0000-000000000003",
            url: "https://example.com/state",
            title: "State",
            isRead: false,
            isLiked: false
        )
        try await repository.upsert(item)

        try await repository.setRead(
            canonicalURL: item.canonicalURL,
            isRead: true,
            at: now
        )
        try await repository.setLiked(
            canonicalURL: item.canonicalURL,
            isLiked: true,
            at: now
        )

        let found = try await repository.find(canonicalURL: item.canonicalURL)
        let stored = try XCTUnwrap(found)
        XCTAssertTrue(stored.isRead)
        XCTAssertTrue(stored.isLiked)
        let readURLs = try await repository.readURLs()
        XCTAssertEqual(readURLs, [stored.canonicalURL])
    }

    func testPreviouslyRecommendedURLsUsesNinetyDayBoundary() async throws {
        let database = try AppDatabase.inMemory()
        let now = Date(unixMilliseconds: 2_000_000_000_000)
        let repository = GRDBArticleRepository(
            database: database,
            clock: FixedClock(instant: now)
        )
        let recent = article(
            id: "20000000-0000-0000-0000-000000000004",
            url: "https://example.com/recent",
            title: "Recent",
            isRead: false,
            isLiked: false
        )
        let old = article(
            id: "20000000-0000-0000-0000-000000000005",
            url: "https://example.com/old",
            title: "Old",
            isRead: false,
            isLiked: false
        )
        try await repository.upsert(recent)
        try await repository.upsert(old)

        try await database.writer.write { database in
            try Self.insertBriefing(
                articleID: recent.id,
                triggeredAt: now.addingTimeInterval(-90 * 86_400),
                in: database
            )
            try Self.insertBriefing(
                articleID: old.id,
                triggeredAt: now.addingTimeInterval(-90 * 86_400 - 1),
                in: database
            )
        }

        let previouslyRecommendedURLs = try await repository.previouslyRecommendedURLs()
        XCTAssertEqual(previouslyRecommendedURLs, [recent.canonicalURL])
    }

    func testFeedbackSignalsAndSavedArticlesPersist() async throws {
        let database = try AppDatabase.inMemory()
        let now = Date(unixMilliseconds: 2_000_000_000_000)
        let repository = GRDBArticleRepository(
            database: database,
            clock: FixedClock(instant: now)
        )
        let excluded = article(
            id: "20000000-0000-0000-0000-000000000006",
            url: "https://example.com/excluded",
            title: "Excluded",
            isRead: false,
            isLiked: false
        )
        let preferred = Article(
            id: ArticleID(rawValue: UUID(uuidString:
                "20000000-0000-0000-0000-000000000007")!),
            canonicalURL: URL(string: "https://example.com/preferred")!,
            title: "React patterns",
            sourceName: "Frontend Weekly",
            sourceURL: nil,
            publishedAt: now,
            isRead: false,
            isLiked: false,
            createdAt: now,
            updatedAt: now,
            topic: .aiAndFrontend
        )
        try await repository.upsert(excluded)
        try await repository.upsert(preferred)

        try await repository.setFeedback(
            canonicalURL: excluded.canonicalURL,
            feedback: .notInterested,
            at: now
        )
        try await repository.setFeedback(
            canonicalURL: preferred.canonicalURL,
            feedback: .moreLikeThis,
            at: now
        )
        try await repository.setLiked(
            canonicalURL: preferred.canonicalURL,
            isLiked: true,
            at: now
        )

        let signals = try await repository.feedbackSignals()
        XCTAssertEqual(signals.excludedURLs, [excluded.canonicalURL])
        XCTAssertEqual(signals.preferredTopicCounts[.aiAndFrontend], 1)
        XCTAssertEqual(signals.preferredSourceCounts["frontend weekly"], 1)
        let saved = try await repository.savedArticles(limit: 5)
        XCTAssertEqual(saved.map(\.canonicalURL), [preferred.canonicalURL])
        XCTAssertEqual(saved.first?.feedback, .moreLikeThis)
    }

    private func article(
        id: String,
        url: String,
        title: String,
        isRead: Bool,
        isLiked: Bool
    ) -> Article {
        Article(
            id: ArticleID(rawValue: UUID(uuidString: id)!),
            canonicalURL: URL(string: url)!,
            title: title,
            sourceName: "Morae Fixture",
            sourceURL: URL(string: "https://source.invalid/feed.xml"),
            publishedAt: Date(unixMilliseconds: 1_999_000_000_000),
            isRead: isRead,
            isLiked: isLiked,
            createdAt: Date(unixMilliseconds: 1_998_000_000_000),
            updatedAt: Date(unixMilliseconds: 1_999_500_000_000)
        )
    }

    private static func insertBriefing(
        articleID: ArticleID,
        triggeredAt: Date,
        in database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO briefing_runs (
                    id, briefing_day, status, selected_article_id,
                    triggered_at_ms, finished_at_ms
                ) VALUES (?, ?, 'succeeded', ?, ?, ?)
                """,
            arguments: [
                UUID().uuidString.lowercased(),
                "2033-05-18",
                articleID.storageValue,
                triggeredAt.unixMilliseconds,
                triggeredAt.unixMilliseconds,
            ]
        )
    }
}
