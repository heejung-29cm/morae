import Foundation
import GRDB
import MoraeCore
import XCTest
@testable import MoraeApp

final class GenerateBriefingTests: XCTestCase {
    func testNormalFlowFetchesAtMostFourFeedsAndStoresOneResult() async throws {
        let database = try AppDatabase.inMemory()
        let todoRepository = GRDBTodoRepository(database: database)
        let feedSourceRepository = GRDBFeedSourceRepository(database: database)
        let articleRepository = GRDBArticleRepository(
            database: database,
            clock: FixedClock(instant: Self.now)
        )
        let briefingRepository = GRDBBriefingRepository(
            database: database,
            uuidGenerator: SequenceUUIDGenerator(
                values: [Self.runUUID, Self.articleUUID]
            )
        )
        try await feedSourceRepository.seedDefaults(Self.sources)
        try await insertSummaryTodos(into: todoRepository)
        let feedClient = CountingFeedClient()
        let generator = GenerateBriefing(
            todoRepository: todoRepository,
            feedSourceRepository: feedSourceRepository,
            feedClient: feedClient,
            articleRepository: articleRepository,
            briefingRepository: briefingRepository,
            preferences: StaticBriefingPreferences(
                values: ["Swift", "concurrency"]
            ),
            clock: FixedClock(instant: Self.now),
            uuidGenerator: SequenceUUIDGenerator(
                values: [Self.articleUUID]
            ),
            calendar: Self.calendar
        )

        let result = await generator.execute(day: Self.today)

        guard case let .generated(generated) = result else {
            return XCTFail("Expected generated result, got \(result)")
        }
        let requestCount = await feedClient.requestCount()
        XCTAssertEqual(requestCount, 4)
        XCTAssertEqual(generated.localTasks.yesterdayCompleted.count, 1)
        XCTAssertEqual(generated.localTasks.todayPending.count, 1)
        XCTAssertEqual(generated.localTasks.mostImportantTodoID, Self.todoID)
        XCTAssertEqual(generated.failedFeedCount, 0)
        XCTAssertEqual(generated.stored.run.status, .succeeded)
        XCTAssertEqual(
            generated.stored.article?.canonicalURL.absoluteString,
            "https://articles.invalid/swift"
        )

        let counts = try database.read { database in
            (
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM briefing_runs"
                ),
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM articles"
                )
            )
        }
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 1)
    }

    private func insertSummaryTodos(
        into repository: GRDBTodoRepository
    ) async throws {
        let yesterday = try LocalDay(rawValue: "2026-07-29")
        let completed = try TodoItem(
            id: TodoID(rawValue: UUID()),
            title: "Done",
            day: yesterday,
            status: .completed,
            priority: .normal,
            sortOrder: 0,
            completedAt: Self.now,
            createdAt: Self.now,
            updatedAt: Self.now
        )
        let important = try TodoItem(
            id: Self.todoID,
            title: "Ship Sprint 3",
            day: Self.today,
            status: .pending,
            priority: .important,
            sortOrder: 0,
            createdAt: Self.now,
            updatedAt: Self.now
        )
        try await repository.insert(completed)
        try await repository.insert(important)
    }

    private static let now = Date(unixMilliseconds: 1_775_040_000_000)
    private static let today = try! LocalDay(rawValue: "2026-07-30")
    private static let todoID = TodoID(
        rawValue: UUID(
            uuidString: "32000000-0000-0000-0000-000000000001"
        )!
    )
    private static let runUUID = UUID(
        uuidString: "32000000-0000-0000-0000-000000000002"
    )!
    private static let articleUUID = UUID(
        uuidString: "32000000-0000-0000-0000-000000000003"
    )!
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private static let sources: [FeedSource] = (0..<5).map { index in
        FeedSource(
            id: UUID(),
            name: "Source \(index)",
            feedURL: URL(
                string: "https://feeds.invalid/\(index).xml"
            )!,
            isOfficial: true,
            createdAt: now,
            updatedAt: now
        )
    }
}

private actor CountingFeedClient: FeedClient {
    private var count = 0

    func candidates(
        from source: FeedSource
    ) async throws -> [FeedCandidate] {
        count += 1
        return [
            FeedCandidate(
                sourceID: source.id,
                sourceName: source.name,
                sourceURL: source.feedURL,
                articleURL: URL(
                    string: "https://articles.invalid/swift?utm_source=feed"
                )!,
                title: "Swift concurrency",
                publishedAt: Date(
                    unixMilliseconds: 1_775_039_000_000
                ),
                isOfficialSource: source.isOfficial
            ),
        ]
    }

    func requestCount() -> Int {
        count
    }
}

private struct StaticBriefingPreferences: BriefingPreferences {
    let values: [String]

    func interests() -> [String] {
        values
    }
}

private final class SequenceUUIDGenerator:
    UUIDGenerating,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [UUID]

    init(values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        lock.withLock {
            precondition(!values.isEmpty)
            return values.removeFirst()
        }
    }
}
