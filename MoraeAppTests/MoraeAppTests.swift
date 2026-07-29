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
}

private struct StubMenuBarContentLoader: MenuBarContentLoading {
    let message: String

    func execute() async -> MenuBarContent {
        MenuBarContent(message: message)
    }
}
