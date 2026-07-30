import MoraeCore
import XCTest
@testable import MoraeApp

final class BriefingRepositoryTests: XCTestCase {
    func testCreatesRunningAndFinishesSuccessWithArticleAtomically() async throws {
        let database = try AppDatabase.inMemory()
        let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let repository = GRDBBriefingRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(uuid: runID)
        )
        let day = try LocalDay(rawValue: "2033-05-18")
        let startedAt = Date(unixMilliseconds: 2_000_000_000_000)

        let running = try await repository.createRunning(
            day: day,
            at: startedAt
        )

        XCTAssertEqual(running.id.rawValue, runID)
        XCTAssertEqual(running.status, .running)
        XCTAssertNil(running.finishedAt)

        var succeeded = running
        succeeded.status = .succeeded
        succeeded.finishedAt = startedAt.addingTimeInterval(3)
        let stored = try await repository.finish(
            run: succeeded,
            article: makeArticle()
        )

        XCTAssertEqual(stored.run.status, .succeeded)
        XCTAssertEqual(stored.run.selectedArticleID, stored.article?.id)
        XCTAssertEqual(
            stored.article?.canonicalURL.absoluteString,
            "https://example.com/article"
        )
        let latest = try await repository.latest(day: day)
        XCTAssertEqual(latest, stored)
    }

    func testFinishesFailureWithErrorCodeAndNoArticle() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBBriefingRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(
                uuid: UUID(
                    uuidString: "30000000-0000-0000-0000-000000000002"
                )!
            )
        )
        let day = try LocalDay(rawValue: "2033-05-18")
        let startedAt = Date(unixMilliseconds: 2_000_000_000_000)
        var run = try await repository.createRunning(day: day, at: startedAt)
        run.status = .failed
        run.finishedAt = startedAt.addingTimeInterval(1)
        run.errorCode = .feedUnavailable

        let stored = try await repository.finish(run: run, article: nil)

        XCTAssertEqual(stored.run.status, .failed)
        XCTAssertEqual(stored.run.errorCode, .feedUnavailable)
        XCTAssertNil(stored.article)
    }

    func testInvalidArticleRollsBackRunFinish() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBBriefingRepository(
            database: database,
            uuidGenerator: FixedUUIDGenerator(
                uuid: UUID(
                    uuidString: "30000000-0000-0000-0000-000000000003"
                )!
            )
        )
        let day = try LocalDay(rawValue: "2033-05-18")
        let startedAt = Date(unixMilliseconds: 2_000_000_000_000)
        var run = try await repository.createRunning(day: day, at: startedAt)
        run.status = .succeeded
        run.finishedAt = startedAt.addingTimeInterval(1)
        let invalidArticle = Article(
            id: ArticleID(rawValue: UUID()),
            canonicalURL: URL(fileURLWithPath: "/tmp/article"),
            title: "Invalid",
            sourceName: "Fixture",
            sourceURL: nil,
            publishedAt: nil,
            isRead: false,
            isLiked: false,
            createdAt: startedAt,
            updatedAt: startedAt
        )

        await XCTAssertThrowsErrorAsync(
            try await repository.finish(
                run: run,
                article: invalidArticle
            )
        )

        let latest = try await repository.latest(day: day)
        XCTAssertEqual(latest?.run.status, .running)
        XCTAssertNil(latest?.article)
    }

    private func makeArticle() -> Article {
        let instant = Date(unixMilliseconds: 2_000_000_000_000)
        return Article(
            id: ArticleID(
                rawValue: UUID(
                    uuidString: "31000000-0000-0000-0000-000000000001"
                )!
            ),
            canonicalURL: URL(
                string: "https://EXAMPLE.com/article?utm_source=feed"
            )!,
            title: "Article",
            sourceName: "Fixture",
            sourceURL: URL(string: "https://example.com/feed.xml"),
            publishedAt: instant,
            isRead: false,
            isLiked: false,
            createdAt: instant,
            updatedAt: instant
        )
    }
}
