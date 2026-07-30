import AppKit
import XCTest
import GRDB
import MoraeCore
@testable import MoraeApp

final class MoraeAppTests: XCTestCase {
    func testAppDataDirectoryCreatesMoraeDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppDataDirectory(applicationSupportURL: { root }).prepare()

        XCTAssertEqual(paths.directoryURL.lastPathComponent, "Morae")
        XCTAssertEqual(paths.databaseURL.lastPathComponent, "morae.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.directoryURL.path))
    }

    func testAppDataDirectoryFailureProvidesRecoveryGuidance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not-a-directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = AppDataDirectory(applicationSupportURL: { root })

        XCTAssertThrowsError(try directory.prepare()) { error in
            XCTAssertEqual(error as? AppDataDirectoryError, .directoryInaccessible)
            XCTAssertFalse((error as? LocalizedError)?.errorDescription?.isEmpty ?? true)
            XCTAssertFalse((error as? LocalizedError)?.recoverySuggestion?.isEmpty ?? true)
        }
    }

    @MainActor
    func testAppContainerInjectsSubstituteUseCase() async {
        let loader = StubMenuBarContentLoader(message: "Injected")
        let container = AppContainer(
            clock: SystemClock(),
            menuBarContentLoader: loader
        )

        let content = await container.menuBarContentLoader.execute()

        XCTAssertEqual(content, MenuBarContent(message: "Injected"))
    }

    func testLogCategoriesMatchLLDContract() {
        XCTAssertEqual(
            Set(MoraeLogCategory.allCases.map(\.rawValue)),
            Set([
                "app-lifecycle",
                "database",
                "briefing",
                "feed",
                "agent-ipc",
                "agent-normalization",
                "notification",
            ])
        )
        XCTAssertEqual(MoraeLogger.subsystem, "io.github.heejung-29cm.morae")
    }

    func testPublicLogTokenRedactsForbiddenFieldShapes() {
        let queryURL = PublicLogToken("https://example.com?prompt=secret")
        let projectPath = PublicLogToken("/Users/person/secret-project")
        let rawPayload = PublicLogToken("{\"prompt\":\"secret\"}")

        XCTAssertEqual(queryURL, .redacted)
        XCTAssertEqual(projectPath, .redacted)
        XCTAssertEqual(rawPayload, .redacted)
        XCTAssertEqual(PublicLogToken("feed_unavailable").description, "feed_unavailable")
    }

    func testPublicLogMetadataContainsOnlyWhitelistedValues() {
        let metadata = PublicLogMetadata(
            result: PublicLogToken("failed"),
            durationMilliseconds: 125,
            byteCount: 512,
            httpStatus: 503,
            migrationVersion: 1,
            count: 4,
            errorCode: PublicLogToken("feed_unavailable")
        )

        XCTAssertEqual(
            metadata.description,
            "result=failed duration_ms=125 byte_count=512 http_status=503 "
                + "migration_version=1 count=4 error_code=feed_unavailable"
        )
    }

    func testInMemoryV1MigrationCreatesEntireSchema() throws {
        let database = try AppDatabase.inMemory()

        let objects = try database.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name
                    FROM sqlite_master
                    WHERE type IN ('table', 'index')
                      AND name NOT LIKE 'sqlite_%'
                    """
            )
        }

        XCTAssertTrue(Set([
            "tasks",
            "feed_sources",
            "articles",
            "briefing_runs",
            "agent_runs",
            "agent_events",
            "idx_tasks_day_status_order",
            "idx_articles_published",
            "idx_briefing_runs_day_triggered",
            "idx_agent_runs_recent",
            "idx_agent_runs_retention",
            "idx_agent_runs_open_session",
            "idx_agent_events_run_time",
        ]).isSubset(of: Set(objects)))

        let migrations = try database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations"
            )
        }
        XCTAssertEqual(migrations, ["v1_initial"])
    }

    func testDatabaseEnablesForeignKeysAndBusyTimeout() throws {
        let database = try AppDatabase.inMemory()

        let settings = try database.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA foreign_keys"),
                try Int.fetchOne(db, sql: "PRAGMA busy_timeout")
            )
        }

        XCTAssertEqual(settings.0, 1)
        XCTAssertEqual(settings.1, 3_000)
    }

    func testFileDatabaseUsesWALAndEnforcesTaskCheckConstraint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("morae.sqlite")
        let database = try AppDatabase.open(at: databaseURL)
        let journalMode = try database.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }

        XCTAssertEqual(journalMode?.lowercased(), "wal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertThrowsError(
            try database.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO tasks (
                            id, title, task_day, status, priority, sort_order,
                            created_at_ms, updated_at_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString.lowercased(),
                        "Invalid state",
                        "2026-07-29",
                        "completed",
                        0,
                        0,
                        0,
                        0,
                    ]
                )
            }
        )
    }

    func testSharedClockUUIDDatabaseAndFixtureSupport() throws {
        let instant = Date(unixMilliseconds: 1_775_039_400_123)
        let uuid = UUID(uuidString: "8E5BC6BE-5197-4392-A7D9-780D3EB58033")!
        let temporaryDatabase = try TemporaryDatabase()

        XCTAssertEqual(FixedClock(instant: instant).now(), instant)
        XCTAssertEqual(FixedUUIDGenerator(uuid: uuid).next(), uuid)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDatabase.rootURL
                    .appendingPathComponent("morae.sqlite")
                    .path
            )
        )
        XCTAssertEqual(
            try FixtureLoader.data(named: "sample-response", extension: "json"),
            Data("{\n  \"status\": \"ok\"\n}\n".utf8)
        )
    }

    func testStubURLProtocolReturnsRegisteredResponse() async throws {
        let fixture = try FixtureLoader.data(
            named: "sample-response",
            extension: "json"
        )
        StubURLProtocol.register { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, fixture)
        }
        defer { StubURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(
            for: URLRequest(url: URL(string: "https://fixture.invalid/data")!)
        )

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, fixture)
    }

    func testTodoRecordRoundTripsEveryNullableField() throws {
        let completedAt = Date(unixMilliseconds: 1_775_039_400_000)
        let item = try TodoItem(
            id: TodoID(
                rawValue: UUID(uuidString: "BF1752FD-9756-41A5-A864-C9EAB8E9680E")!
            ),
            title: "  Ship Sprint 1  ",
            day: LocalDay(rawValue: "2026-07-29"),
            status: .completed,
            priority: .important,
            sortOrder: 3,
            estimatedMinutes: 45,
            relatedURL: URL(string: "https://example.com/task"),
            projectPath: "/tmp/morae",
            completedAt: completedAt,
            createdAt: Date(unixMilliseconds: 1_775_039_000_000),
            updatedAt: completedAt
        )

        let restored = try TodoRecord(item: item).domain()

        XCTAssertEqual(restored.title, "Ship Sprint 1")
        XCTAssertEqual(restored, item)
    }

    func testTodoRecordRejectsInvalidEnumValueExplicitly() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
            try db.execute(
                sql: """
                    INSERT INTO tasks (
                        id, title, task_day, status, priority, sort_order,
                        created_at_ms, updated_at_ms
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString.lowercased(),
                    "Bad status",
                    "2026-07-29",
                    "unknown",
                    0,
                    0,
                    1,
                    1,
                ]
            )
        }

        let record = try database.read { db in
            try TodoRecord.fetchOne(db)!
        }

        XCTAssertThrowsError(try record.domain()) { error in
            XCTAssertEqual(error as? TodoMappingError, .invalidStatus("unknown"))
        }
    }

    func testMenuBarSectionsFollowLLDOrderAndHaveEmptyStates() {
        XCTAssertEqual(
            MenuBarSection.orderedCases,
            [.article, .yesterdayCompleted, .todayTodos, .recentAgents]
        )
        XCTAssertTrue(
            MenuBarSection.orderedCases.allSatisfy {
                !$0.title.isEmpty && !$0.emptyMessage.isEmpty
            }
        )
    }

    func testTodoReorderPlanMovesOnlyMeaningfulPendingDrops() {
        let first = TodoID(
            rawValue: UUID(uuidString: "85E52B30-69DD-4685-825E-1B66DCE08D9A")!
        )
        let second = TodoID(
            rawValue: UUID(uuidString: "68211FC7-66D8-4D3E-BBA0-CDBB47E77193")!
        )
        let third = TodoID(
            rawValue: UUID(uuidString: "EBC2F6CD-12AE-4825-B86F-C5075FBE96F9")!
        )
        let original = [first, second, third]

        XCTAssertEqual(
            TodoReorderPlan.moving(third, before: first, in: original)?.orderedIDs,
            [third, first, second]
        )
        XCTAssertNil(
            TodoReorderPlan.moving(first, before: second, in: original)
        )
        XCTAssertNil(
            TodoReorderPlan.moving(first, before: first, in: original)
        )
    }

    @MainActor
    func testMoraeBrandColorsResolveForBothSystemAppearances() throws {
        let accent = try XCTUnwrap(
            NSColor(
                named: NSColor.Name("MoraeAccent"),
                bundle: .main
            )
        )
        let onAccent = try XCTUnwrap(
            NSColor(
                named: NSColor.Name("MoraeOnAccent"),
                bundle: .main
            )
        )
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertNotEqual(
            resolvedColor(accent, appearance: lightAppearance),
            resolvedColor(accent, appearance: darkAppearance)
        )
        XCTAssertNotEqual(
            resolvedColor(onAccent, appearance: lightAppearance),
            resolvedColor(onAccent, appearance: darkAppearance)
        )
    }

    func testMenuBarStateKindsProvideAccessibleFallbacks() {
        let kinds: [MenuBarStateKind] = [.empty, .validation, .error]

        XCTAssertTrue(
            kinds.allSatisfy {
                !$0.defaultSystemImage.isEmpty
                    && !$0.accessibilityPrefix.isEmpty
            }
        )
    }

    private func resolvedColor(
        _ color: NSColor,
        appearance: NSAppearance
    ) -> NSColor? {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return resolved
    }
}

private struct StubMenuBarContentLoader: MenuBarContentLoading {
    let message: String

    func execute() async -> MenuBarContent {
        MenuBarContent(message: message)
    }
}
