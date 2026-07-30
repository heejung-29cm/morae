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

    func testPartialFeedFailureUsesSuccessfulCandidateWithoutRetry() async throws {
        let database = try AppDatabase.inMemory()
        let todoRepository = GRDBTodoRepository(database: database)
        let feedSourceRepository = GRDBFeedSourceRepository(database: database)
        let articleRepository = GRDBArticleRepository(
            database: database,
            clock: FixedClock(instant: Self.now)
        )
        let briefingRepository = GRDBBriefingRepository(
            database: database,
            uuidGenerator: SequenceUUIDGenerator(values: [Self.runUUID])
        )
        let sources = Array(Self.sources.prefix(4))
        try await feedSourceRepository.seedDefaults(sources)
        try await insertSummaryTodos(into: todoRepository)
        let successfulSourceID = sources[0].id
        let feedClient = ScriptedFeedClient(
            successfulSourceIDs: [successfulSourceID]
        )
        let generator = GenerateBriefing(
            todoRepository: todoRepository,
            feedSourceRepository: feedSourceRepository,
            feedClient: feedClient,
            articleRepository: articleRepository,
            briefingRepository: briefingRepository,
            preferences: StaticBriefingPreferences(values: []),
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
        XCTAssertEqual(generated.failedFeedCount, 3)
        XCTAssertEqual(
            generated.stored.article?.sourceName,
            sources[0].name
        )
        for source in sources {
            let count = await feedClient.requestCount(for: source.id)
            XCTAssertEqual(count, 1, "\(source.name) should not retry")
        }
    }

    func testAllFeedFailuresPreserveLocalSummaryAndDoNotRetry() async throws {
        let database = try AppDatabase.inMemory()
        let todoRepository = GRDBTodoRepository(database: database)
        let feedSourceRepository = GRDBFeedSourceRepository(database: database)
        let articleRepository = GRDBArticleRepository(
            database: database,
            clock: FixedClock(instant: Self.now)
        )
        let briefingRepository = GRDBBriefingRepository(
            database: database,
            uuidGenerator: SequenceUUIDGenerator(values: [Self.runUUID])
        )
        let sources = Array(Self.sources.prefix(4))
        try await feedSourceRepository.seedDefaults(sources)
        try await insertSummaryTodos(into: todoRepository)
        let feedClient = ScriptedFeedClient(successfulSourceIDs: [])
        let generator = GenerateBriefing(
            todoRepository: todoRepository,
            feedSourceRepository: feedSourceRepository,
            feedClient: feedClient,
            articleRepository: articleRepository,
            briefingRepository: briefingRepository,
            preferences: StaticBriefingPreferences(values: []),
            clock: FixedClock(instant: Self.now),
            uuidGenerator: SequenceUUIDGenerator(values: []),
            calendar: Self.calendar
        )

        let result = await generator.execute(day: Self.today)

        guard case let .failed(failure) = result else {
            return XCTFail("Expected failed result, got \(result)")
        }
        XCTAssertEqual(failure.code, .feedUnavailable)
        XCTAssertEqual(failure.failedFeedCount, 4)
        XCTAssertEqual(failure.localTasks?.yesterdayCompleted.count, 1)
        XCTAssertEqual(failure.localTasks?.todayPending.count, 1)
        XCTAssertEqual(failure.run?.status, .failed)
        XCTAssertEqual(failure.run?.errorCode, .feedUnavailable)
        for source in sources {
            let count = await feedClient.requestCount(for: source.id)
            XCTAssertEqual(count, 1, "\(source.name) should not retry")
        }

        let articleCount = try database.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM articles"
            )
        }
        XCTAssertEqual(articleCount, 0)
    }

    @MainActor
    func testViewModelTransitionsFromIdleToLoadingAndBlocksDuplicateTrigger()
        async
    {
        let generator = SuspendedBriefingGenerator()
        let viewModel = MenuBarViewModel(
            repository: nil,
            briefingGenerator: generator,
            clock: FixedClock(instant: Self.now),
            calendar: Self.calendar
        )
        XCTAssertEqual(viewModel.briefingState, .idle(previous: nil))

        let generation = Task { @MainActor in
            await viewModel.generateBriefing()
        }
        while await generator.requestCount() == 0 {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.briefingState, .loading(previous: nil))

        await viewModel.generateBriefing()
        let requestCount = await generator.requestCount()
        XCTAssertEqual(requestCount, 1)

        let failure = FailedBriefing(
            run: nil,
            localTasks: nil,
            code: .feedUnavailable,
            failedFeedCount: 4
        )
        await generator.resolve(with: .failed(failure))
        await generation.value
        XCTAssertEqual(
            viewModel.briefingState,
            .failure(failure, previous: nil)
        )
    }

    @MainActor
    func testViewModelTransitionsToSuccess() async {
        let generated = Self.generatedBriefing
        let viewModel = MenuBarViewModel(
            repository: nil,
            briefingGenerator: StaticBriefingGenerator(
                result: .generated(generated)
            ),
            clock: FixedClock(instant: Self.now),
            calendar: Self.calendar
        )

        await viewModel.generateBriefing()

        XCTAssertEqual(viewModel.briefingState, .success(generated))
    }

    @MainActor
    func testBriefingRequestGeneratesImmediatelyWithoutAddingTodo()
        async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let generator = CountingResultBriefingGenerator(
            result: .failed(
                FailedBriefing(
                    run: nil,
                    localTasks: nil,
                    code: .feedUnavailable,
                    failedFeedCount: 0
                )
            )
        )
        let viewModel = MenuBarViewModel(
            repository: repository,
            briefingGenerator: generator,
            clock: FixedClock(instant: Self.now),
            calendar: Self.calendar
        )

        await viewModel.requestBriefing()

        let requestCount = await generator.requestCount()
        XCTAssertEqual(requestCount, 1)
        let todos = try await repository.list(day: viewModel.today)
        XCTAssertTrue(todos.isEmpty)

        await viewModel.requestBriefing()
        let secondRequestCount = await generator.requestCount()
        XCTAssertEqual(secondRequestCount, 2)
    }

    @MainActor
    func testManualRerunCreatesOneRunAndLatestSurvivesDatabaseReopen()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("morae.sqlite")
        let runOneID = UUID(
            uuidString: "33000000-0000-0000-0000-000000000001"
        )!
        let runTwoID = UUID(
            uuidString: "33000000-0000-0000-0000-000000000002"
        )!
        let source = FeedSource(
            id: UUID(),
            name: "Restart Feed",
            feedURL: URL(string: "https://feeds.invalid/restart.xml")!,
            isOfficial: true,
            createdAt: Self.restartNow,
            updatedAt: Self.restartNow
        )
        let feedClient = ScriptedFeedClient(
            successfulSourceIDs: [source.id],
            publishedAt: Self.restartNow
        )

        do {
            let database = try AppDatabase.open(at: databaseURL)
            defer { try? database.close() }
            let todoRepository = GRDBTodoRepository(database: database)
            let feedRepository = GRDBFeedSourceRepository(database: database)
            let articleRepository = GRDBArticleRepository(
                database: database,
                clock: FixedClock(instant: Self.restartNow)
            )
            let briefingRepository = GRDBBriefingRepository(
                database: database,
                uuidGenerator: SequenceUUIDGenerator(values: [runOneID])
            )
            try await feedRepository.seedDefaults([source])
            let generator = GenerateBriefing(
                todoRepository: todoRepository,
                feedSourceRepository: feedRepository,
                feedClient: feedClient,
                articleRepository: articleRepository,
                briefingRepository: briefingRepository,
                preferences: StaticBriefingPreferences(values: []),
                clock: FixedClock(instant: Self.restartNow),
                uuidGenerator: SequenceUUIDGenerator(values: [UUID()]),
                calendar: Self.calendar
            )

            let firstResult = await generator.execute(day: Self.today)
            guard case .generated = firstResult else {
                return XCTFail("Expected first generated result")
            }
        }

        do {
            let database = try AppDatabase.open(at: databaseURL)
            defer { try? database.close() }
            let todoRepository = GRDBTodoRepository(database: database)
            let feedRepository = GRDBFeedSourceRepository(database: database)
            let articleRepository = GRDBArticleRepository(
                database: database,
                clock: FixedClock(instant: Self.restartNow)
            )
            let briefingRepository = GRDBBriefingRepository(
                database: database,
                uuidGenerator: SequenceUUIDGenerator(values: [runTwoID])
            )
            let generator = GenerateBriefing(
                todoRepository: todoRepository,
                feedSourceRepository: feedRepository,
                feedClient: feedClient,
                articleRepository: articleRepository,
                briefingRepository: briefingRepository,
                preferences: StaticBriefingPreferences(values: []),
                clock: FixedClock(instant: Self.restartNow),
                uuidGenerator: SequenceUUIDGenerator(values: [UUID()]),
                calendar: Self.calendar
            )
            let viewModel = MenuBarViewModel(
                repository: todoRepository,
                briefingRepository: briefingRepository,
                briefingGenerator: generator,
                clock: FixedClock(instant: Self.restartNow),
                calendar: Self.calendar
            )
            await viewModel.onAppear()

            guard case let .success(restored) = viewModel.briefingState else {
                return XCTFail("Expected restored first briefing")
            }
            XCTAssertEqual(restored.stored.run.id.rawValue, runOneID)
            await viewModel.requestBriefing()

            let runCount = try database.read { database in
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM briefing_runs"
                )
            }
            XCTAssertEqual(runCount, 2)
            viewModel.onDisappear()
        }

        do {
            let database = try AppDatabase.open(at: databaseURL)
            defer { try? database.close() }
            let todoRepository = GRDBTodoRepository(database: database)
            let briefingRepository = GRDBBriefingRepository(
                database: database,
                uuidGenerator: SequenceUUIDGenerator(values: [])
            )
            let viewModel = MenuBarViewModel(
                repository: todoRepository,
                briefingRepository: briefingRepository,
                clock: FixedClock(instant: Self.restartNow),
                calendar: Self.calendar
            )

            await viewModel.onAppear()

            guard case let .success(restored) = viewModel.briefingState else {
                return XCTFail("Expected restored latest briefing")
            }
            XCTAssertEqual(restored.stored.run.id.rawValue, runTwoID)
            XCTAssertNotNil(restored.stored.article)
            viewModel.onDisappear()
        }
        let requestCount = await feedClient.requestCount(for: source.id)
        XCTAssertEqual(requestCount, 2)
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
    private static let restartNow = Date(
        unixMilliseconds: 1_785_412_800_000
    )
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
    private static var generatedBriefing: GeneratedBriefing {
        let articleID = ArticleID(rawValue: articleUUID)
        let article = Article(
            id: articleID,
            canonicalURL: URL(string: "https://articles.invalid/state")!,
            title: "State machines",
            sourceName: "Morae",
            sourceURL: URL(string: "https://feeds.invalid/state.xml"),
            publishedAt: now,
            isRead: false,
            isLiked: false,
            createdAt: now,
            updatedAt: now
        )
        let run = BriefingRun(
            id: BriefingRunID(rawValue: runUUID),
            day: today,
            status: .succeeded,
            selectedArticleID: articleID,
            triggeredAt: now,
            finishedAt: now
        )
        return GeneratedBriefing(
            stored: StoredBriefing(run: run, article: article),
            localTasks: LocalTaskSummary(
                yesterdayCompleted: [],
                todayPending: [],
                todayCompletedCount: 0,
                todayEstimatedMinutes: 0,
                mostImportantTodoID: nil
            ),
            failedFeedCount: 0
        )
    }
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

private actor ScriptedFeedClient: FeedClient {
    private let successfulSourceIDs: Set<UUID>
    private let publishedAt: Date
    private var counts: [UUID: Int] = [:]

    init(
        successfulSourceIDs: Set<UUID>,
        publishedAt: Date = Date(
            unixMilliseconds: 1_775_039_000_000
        )
    ) {
        self.successfulSourceIDs = successfulSourceIDs
        self.publishedAt = publishedAt
    }

    func candidates(
        from source: FeedSource
    ) async throws -> [FeedCandidate] {
        counts[source.id, default: 0] += 1
        guard successfulSourceIDs.contains(source.id) else {
            throw ScriptedFeedError.unavailable
        }
        return [
            FeedCandidate(
                sourceID: source.id,
                sourceName: source.name,
                sourceURL: source.feedURL,
                articleURL: URL(
                    string: "https://articles.invalid/\(source.id)"
                )!,
                title: "Available article",
                publishedAt: publishedAt,
                isOfficialSource: source.isOfficial
            ),
        ]
    }

    func requestCount(for sourceID: UUID) -> Int {
        counts[sourceID, default: 0]
    }
}

private enum ScriptedFeedError: Error {
    case unavailable
}

private actor SuspendedBriefingGenerator: BriefingGenerating {
    private var count = 0
    private var continuation: CheckedContinuation<BriefingResult, Never>?

    func execute(day _: LocalDay) async -> BriefingResult {
        count += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func requestCount() -> Int {
        count
    }

    func resolve(with result: BriefingResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private struct StaticBriefingGenerator: BriefingGenerating {
    let result: BriefingResult

    func execute(day _: LocalDay) async -> BriefingResult {
        result
    }
}

private actor CountingResultBriefingGenerator: BriefingGenerating {
    private let result: BriefingResult
    private var count = 0

    init(result: BriefingResult) {
        self.result = result
    }

    func execute(day _: LocalDay) async -> BriefingResult {
        count += 1
        return result
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
