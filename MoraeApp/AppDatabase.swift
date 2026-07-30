import Foundation
import GRDB
import MoraeCore

final class AppDatabase: @unchecked Sendable {
    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func open(at databaseURL: URL) throws -> AppDatabase {
        let pool = try DatabasePool(
            path: databaseURL.path,
            configuration: makeConfiguration()
        )
        try pool.writeWithoutTransaction { database in
            let mode = try String.fetchOne(
                database,
                sql: "PRAGMA journal_mode = WAL"
            )
            guard mode?.lowercased() == "wal" else {
                throw AppError(
                    code: "database_wal_unavailable",
                    userMessage: "Morae could not configure its local database.",
                    recovery: "Check disk availability, then reopen Morae."
                )
            }
        }
        try makeMigrator().migrate(pool)
        return AppDatabase(writer: pool)
    }

    static func inMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue(configuration: makeConfiguration())
        try makeMigrator().migrate(queue)
        return AppDatabase(writer: queue)
    }

    func read<Value>(
        _ value: (Database) throws -> Value
    ) throws -> Value {
        try writer.read(value)
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: "PRAGMA busy_timeout = 3000")
        }
        return configuration
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { database in
            try database.execute(sql: SchemaV1.sql)
        }
        migrator.registerMigration("v2_unique_carry_over") { database in
            try database.execute(sql: """
                CREATE UNIQUE INDEX idx_tasks_carry_target_source
                ON tasks(task_day, source)
                WHERE source LIKE 'carryover:%'
                """)
        }
        migrator.registerMigration("v3_app_metadata") { database in
            try database.execute(sql: """
                CREATE TABLE app_metadata (
                    key     TEXT PRIMARY KEY NOT NULL,
                    value   TEXT NOT NULL
                )
                """)
        }
        return migrator
    }
}

private enum SchemaV1 {
    static let sql = """
        CREATE TABLE tasks (
            id                  TEXT PRIMARY KEY NOT NULL,
            title               TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 200),
            task_day            TEXT NOT NULL CHECK(length(task_day) = 10),
            status              TEXT NOT NULL CHECK(status IN ('pending', 'completed')),
            priority            INTEGER NOT NULL DEFAULT 0 CHECK(priority IN (0, 1)),
            sort_order          INTEGER NOT NULL,
            estimated_minutes   INTEGER CHECK(estimated_minutes BETWEEN 1 AND 1440),
            related_url         TEXT,
            project_path        TEXT,
            source              TEXT NOT NULL DEFAULT 'manual',
            completed_at_ms     INTEGER,
            created_at_ms       INTEGER NOT NULL,
            updated_at_ms       INTEGER NOT NULL,
            CHECK (
                (status = 'completed' AND completed_at_ms IS NOT NULL)
                OR (status = 'pending' AND completed_at_ms IS NULL)
            )
        );

        CREATE INDEX idx_tasks_day_status_order
        ON tasks(task_day, status, sort_order);

        CREATE TABLE feed_sources (
            id                  TEXT PRIMARY KEY NOT NULL,
            name                TEXT NOT NULL,
            feed_url            TEXT NOT NULL UNIQUE,
            is_official         INTEGER NOT NULL DEFAULT 0 CHECK(is_official IN (0, 1)),
            is_enabled          INTEGER NOT NULL DEFAULT 1 CHECK(is_enabled IN (0, 1)),
            last_checked_at_ms  INTEGER,
            created_at_ms       INTEGER NOT NULL,
            updated_at_ms       INTEGER NOT NULL
        );

        CREATE TABLE articles (
            id                      TEXT PRIMARY KEY NOT NULL,
            canonical_url           TEXT NOT NULL UNIQUE,
            title                   TEXT NOT NULL,
            source_name             TEXT NOT NULL,
            source_url              TEXT,
            published_at_ms         INTEGER,
            is_read                 INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0, 1)),
            is_liked                INTEGER NOT NULL DEFAULT 0 CHECK(is_liked IN (0, 1)),
            created_at_ms           INTEGER NOT NULL,
            updated_at_ms           INTEGER NOT NULL
        );

        CREATE INDEX idx_articles_published
        ON articles(published_at_ms DESC);

        CREATE TABLE briefing_runs (
            id                  TEXT PRIMARY KEY NOT NULL,
            briefing_day        TEXT NOT NULL CHECK(length(briefing_day) = 10),
            status              TEXT NOT NULL CHECK(status IN (
                'running', 'succeeded', 'failed'
            )),
            selected_article_id TEXT REFERENCES articles(id) ON DELETE SET NULL,
            triggered_at_ms     INTEGER NOT NULL,
            finished_at_ms      INTEGER,
            error_code          TEXT
        );

        CREATE INDEX idx_briefing_runs_day_triggered
        ON briefing_runs(briefing_day, triggered_at_ms DESC);

        CREATE TABLE agent_runs (
            id                  TEXT PRIMARY KEY NOT NULL,
            source              TEXT NOT NULL CHECK(source IN ('codex', 'claude')),
            session_id          TEXT NOT NULL,
            turn_id             TEXT NOT NULL,
            project_path        TEXT,
            title               TEXT,
            status              TEXT NOT NULL CHECK(status IN (
                'running', 'attention_required', 'responded',
                'completed', 'failed', 'cancelled'
            )),
            started_at_ms       INTEGER,
            received_at_ms      INTEGER NOT NULL,
            updated_at_ms       INTEGER NOT NULL,
            closed_at_ms        INTEGER,
            closure_reason      TEXT CHECK(closure_reason IN (
                'terminal_event', 'superseded'
            )),
            last_message        TEXT,
            is_unread           INTEGER NOT NULL DEFAULT 1 CHECK(is_unread IN (0, 1)),
            UNIQUE(source, session_id, turn_id)
        );

        CREATE INDEX idx_agent_runs_recent
        ON agent_runs(updated_at_ms DESC);

        CREATE INDEX idx_agent_runs_retention
        ON agent_runs(received_at_ms);

        CREATE INDEX idx_agent_runs_open_session
        ON agent_runs(source, session_id, closed_at_ms);

        CREATE TABLE agent_events (
            id                  TEXT PRIMARY KEY NOT NULL,
            agent_run_id        TEXT NOT NULL
                                    REFERENCES agent_runs(id) ON DELETE CASCADE,
            event_key           TEXT NOT NULL UNIQUE,
            source_event        TEXT NOT NULL,
            normalized_status   TEXT NOT NULL,
            occurred_at_ms      INTEGER NOT NULL,
            received_at_ms      INTEGER NOT NULL
        );

        CREATE INDEX idx_agent_events_run_time
        ON agent_events(agent_run_id, occurred_at_ms);
        """
}
