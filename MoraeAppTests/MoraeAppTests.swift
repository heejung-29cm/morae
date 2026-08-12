import AppKit
import XCTest
import GRDB
import MoraeCore
@testable import MoraeApp

final class MoraeAppTests: XCTestCase {
    @MainActor
    func testHamsterMenuBarIconUsesAllFramesAndRestsOnFrameSix() {
        XCTAssertEqual(HamsterMenuBarIcon.frames.count, 13)
        XCTAssertEqual(HamsterMenuBarIcon.restingFrameNumber, 6)
        XCTAssertEqual(HamsterMenuBarIcon.canvasSize, 14)
        XCTAssertEqual(HamsterMenuBarIcon.glyphSize, 14)
        XCTAssertTrue(
            HamsterMenuBarIcon.frames.allSatisfy {
                $0.size == NSSize(width: 14, height: 14)
            }
        )
        XCTAssertNotNil(
            HamsterMenuBarIcon.frame(at: .distantPast, animated: false)
        )
    }

    @MainActor
    func testMenuBarRightClickRecognizesStatusItemHierarchy() {
        let rootView = NSView(frame: .zero)
        XCTAssertFalse(
            MoraeApplicationDelegate.containsStatusBarButton(in: rootView)
        )

        rootView.addSubview(NSStatusBarButton(frame: .zero))

        XCTAssertTrue(
            MoraeApplicationDelegate.containsStatusBarButton(in: rootView)
        )
        XCTAssertEqual(
            MoraeApplicationDelegate.quitMenuTitle,
            "Morae 종료"
        )
    }

    func testAgentRunGroupingShowsTwoRecentFoldersAndTwoRunsEach() {
        let baseDate = Date(unixMilliseconds: 1_800_000_000_000)
        func run(
            _ turnID: String,
            path: String,
            secondsAgo: TimeInterval
        ) -> AgentRun {
            AgentRun(
                id: AgentRunID(rawValue: UUID()),
                source: .codex,
                sessionID: "session-\(turnID)",
                turnID: turnID,
                projectPath: path,
                status: .completed,
                receivedAt: baseDate.addingTimeInterval(-secondsAgo),
                updatedAt: baseDate.addingTimeInterval(-secondsAgo)
            )
        }

        let groups = AgentRunGrouping.recentGroups(
            from: [
                run("alpha-old", path: "/Users/me/Repos/alpha", secondsAgo: 50),
                run("other-alpha", path: "/Other/Repos/alpha", secondsAgo: 30),
                run("beta-new", path: "/Users/me/Repos/beta", secondsAgo: 10),
                run("alpha-new", path: "/Users/me/Repos/alpha", secondsAgo: 0),
                run("beta-old", path: "/Users/me/Repos/beta", secondsAgo: 40),
                run("alpha-middle", path: "/Users/me/Repos/alpha", secondsAgo: 20),
            ]
        )

        XCTAssertEqual(groups.map(\.title), ["Repos/alpha", "Repos/beta"])
        XCTAssertEqual(
            groups.map { $0.runs.map(\.turnID) },
            [
                ["alpha-new", "alpha-middle"],
                ["beta-new", "beta-old"],
            ]
        )
        XCTAssertEqual(groups.count, AgentRunGrouping.groupLimit)
        XCTAssertTrue(
            groups.allSatisfy {
                $0.runs.count == AgentRunGrouping.runsPerGroup
            }
        )
    }

    func testAppDataDirectoryCreatesMoraeDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = try AppDataDirectory(applicationSupportURL: { root }).prepare()

        XCTAssertEqual(paths.directoryURL.lastPathComponent, "Morae")
        XCTAssertEqual(paths.databaseURL.lastPathComponent, "morae.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.directoryURL.path))
    }

    func testFreshTestProfileUsesIsolatedPerProcessLocations() {
        let profile = MoraeRuntimeProfile.current(
            arguments: ["Morae", "--fresh-test-profile"],
            processID: 4242
        )

        XCTAssertEqual(profile, .freshTest(sessionID: "4242"))
        XCTAssertTrue(profile.isFreshTest)
        XCTAssertEqual(profile.displayName, "첫 실행 테스트 모드")
        XCTAssertTrue(
            profile.sessionRootURL?.path.hasSuffix(
                "morae-fresh-test-\(getuid())-4242"
            ) == true
        )
        XCTAssertEqual(
            profile.defaultsSuiteName,
            "io.github.heejung-29cm.morae.fresh-test.4242"
        )
        XCTAssertEqual(
            MoraeRuntimeProfile.current(
                arguments: ["Morae"],
                processID: 4242
            ),
            .standard
        )
    }

    func testFreshTestJiraCredentialsStayInMemory() throws {
        let store = InMemoryJiraCredentialStore()

        try store.save(token: "test-token", accountEmail: "me@example.com")
        XCTAssertEqual(
            try store.load(accountEmail: "me@example.com"),
            "test-token"
        )

        try store.delete(accountEmail: "me@example.com")
        XCTAssertNil(try store.load(accountEmail: "me@example.com"))
    }

    @MainActor
    func testFreshTestContainerStartsEmptyAndDoesNotOpenAgentSocket()
        async throws
    {
        let profile = MoraeRuntimeProfile.freshTest(
            sessionID: UUID().uuidString
        )
        let sessionRootURL = try XCTUnwrap(profile.sessionRootURL)

        let container = AppContainer.live(profile: profile)
        let repository = try XCTUnwrap(container.todoRepository)
        let today = container.clock.localDay(
            for: container.clock.now(),
            calendar: .autoupdatingCurrent
        )

        let items = try await repository.list(day: today)
        let jiraIntegration = try XCTUnwrap(container.jiraIntegration)
        let jiraSnapshot = await jiraIntegration.snapshot()

        XCTAssertTrue(items.isEmpty)
        XCTAssertNil(jiraSnapshot.connection)
        XCTAssertNil(container.agentSocketServer)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionRootURL.path
            )
        )

        try container.database?.close()
        profile.cleanUp()
        try FileManager.default.removeItem(at: sessionRootURL)
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
                "jira",
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

    func testInMemoryMigrationsCreateEntireSchema() throws {
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
            "app_metadata",
            "jira_task_dismissals",
            "idx_tasks_day_status_order",
            "idx_tasks_carry_target_source",
            "idx_tasks_external_daily",
            "idx_tasks_external_provider",
            "idx_articles_published",
            "idx_articles_feedback",
            "idx_briefing_runs_day_triggered",
            "idx_agent_runs_recent",
            "idx_agent_runs_retention",
            "idx_agent_runs_open_session",
            "idx_agent_events_run_time",
            "ai_reports",
            "idx_ai_reports_day",
        ]).isSubset(of: Set(objects)))

        let migrations = try database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations"
            )
        }
        XCTAssertEqual(
            migrations,
            [
                "v1_initial",
                "v2_unique_carry_over",
                "v3_app_metadata",
                "v4_feed_selection_weight",
                "v5_jira_task_origin",
                "v6_jira_daily_dismissal",
                "v7_article_feedback",
                "v8_ai_reports",
            ]
        )
    }

    func testOnboardingCompletionIsVersionedAndPersistent() {
        let suite = "MoraeAppTests.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsOnboardingStateStore(defaults: defaults)

        XCTAssertFalse(store.isCompleted())
        store.markCompleted()
        XCTAssertTrue(store.isCompleted())
        XCTAssertTrue(
            UserDefaultsOnboardingStateStore(defaults: defaults).isCompleted()
        )
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
        defer { try? database.close() }
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
            [
                .article,
                .aiReport,
                .yesterdayCompleted,
                .todayTodos,
                .recentAgents,
            ]
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
        XCTAssertEqual(
            TodoReorderPlan.moving(first, before: nil, in: original)?.orderedIDs,
            [second, third, first]
        )
        XCTAssertNil(
            TodoReorderPlan.moving(first, before: second, in: original)
        )
        XCTAssertNil(
            TodoReorderPlan.moving(third, before: nil, in: original)
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

    func testSettingsStoreFallsBackFromMalformedValuesAndPersistsTypedValues() {
        let suite = "MoraeAppTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future", forKey: MoraeSettingKey.schemaVersion)
        defaults.set("yes", forKey: MoraeSettingKey.launchAtLogin)
        defaults.set([1, 2], forKey: MoraeSettingKey.interests)
        defaults.set(1, forKey: MoraeSettingKey.storeAgentTitle)
        let store = UserDefaultsSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), MoraeSettings())

        let expected = MoraeSettings(
            launchAtLogin: true,
            interests: ["AI", "Frontend"],
            storeProjectPath: true,
            storeAgentTitle: true,
            storeLastMessage: true,
            showDetailsInNotification: true
        )
        store.save(expected)
        XCTAssertEqual(store.load(), expected)
        XCTAssertEqual(
            defaults.integer(forKey: MoraeSettingKey.schemaVersion),
            MoraeSettings.schemaVersion
        )
    }

    func testHookSnippetsUseBundledExecutableAndValidClaudeJSON() throws {
        let helperURL = URL(
            fileURLWithPath: "/Applications/Morae.app/Contents/MacOS/hamster-event"
        )

        XCTAssertEqual(
            HookSnippetBuilder.codex(helperURL: helperURL),
            #"notify = ["/Applications/Morae.app/Contents/MacOS/hamster-event"]"#
        )
        let claude = HookSnippetBuilder.claude(helperURL: helperURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(claude.utf8))
                as? [String: Any]
        )
        XCTAssertNotNil(object["hooks"])
        XCTAssertTrue(claude.contains("claude-task-completed"))
        XCTAssertTrue(claude.contains("claude-stop-failure"))
    }

    func testAutomaticHookSetupPreservesExistingCodexNotifyAndClaudeSettings()
        throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent(
            "support",
            isDirectory: true
        )
        let source = root.appendingPathComponent("hamster-event")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: source)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: source.path
        )
        let codexURL = home.appendingPathComponent(".codex/config.toml")
        let originalCodex =
            "model = \"gpt-test\"\nnotify = [\"/existing/notifier\", \"turn-ended\"]\n\n[features]\napps = true\n"
        try Data(originalCodex.utf8).write(to: codexURL)
        let claudeURL = home.appendingPathComponent(
            ".claude/settings.json"
        )
        let originalClaude = """
        {
          "permissions": {"defaultMode": "acceptEdits"},
          "hooks": {
            "Stop": [{
              "hooks": [{
                "type": "command",
                "command": "/existing/stop-hook"
              }]
            }]
          }
        }
        """
        try Data(originalClaude.utf8).write(to: claudeURL)
        let installer = LiveAgentHookInstaller(
            homeDirectoryURL: home,
            applicationSupportURL: support
        )

        try installer.install(.codex, sourceHelperURL: source)
        try installer.install(.claude, sourceHelperURL: source)

        XCTAssertEqual(installer.status(for: .codex), .installed)
        XCTAssertEqual(installer.status(for: .claude), .installed)
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: installer.installedHelperURL().path
            )
        )
        let codex = try String(contentsOf: codexURL, encoding: .utf8)
        XCTAssertTrue(codex.contains("--morae-codex-relay"))
        XCTAssertTrue(codex.contains("[features]"))
        XCTAssertEqual(
            try String(
                contentsOf: codexURL.appendingPathExtension("morae-backup"),
                encoding: .utf8
            ),
            originalCodex
        )
        let claudeData = try Data(contentsOf: claudeURL)
        let claude = try XCTUnwrap(
            JSONSerialization.jsonObject(with: claudeData)
                as? [String: Any]
        )
        XCTAssertNotNil(claude["permissions"])
        XCTAssertTrue(
            String(decoding: claudeData, as: UTF8.self)
                .contains("/existing/stop-hook")
        )

        let codexBeforeSecondInstall = codex
        try installer.install(.codex, sourceHelperURL: source)
        XCTAssertEqual(
            try String(contentsOf: codexURL, encoding: .utf8),
            codexBeforeSecondInstall
        )
    }

    func testAutomaticHookSetupDoesNotOverwriteInvalidClaudeJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent(
            "support",
            isDirectory: true
        )
        let source = root.appendingPathComponent("hamster-event")
        let claudeDirectory = home.appendingPathComponent(
            ".claude",
            isDirectory: true
        )
        let claudeURL = claudeDirectory.appendingPathComponent(
            "settings.json"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: source)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: source.path
        )
        let invalid = Data("{ invalid".utf8)
        try invalid.write(to: claudeURL)
        let installer = LiveAgentHookInstaller(
            homeDirectoryURL: home,
            applicationSupportURL: support
        )

        XCTAssertThrowsError(
            try installer.install(.claude, sourceHelperURL: source)
        )
        XCTAssertEqual(try Data(contentsOf: claudeURL), invalid)
    }

    @MainActor
    func testSettingsWindowMovesToActiveSpace() {
        XCTAssertEqual(MoraeSettingsWindowController.title, "모래 설정")
        XCTAssertTrue(
            MoraeSettingsWindowController.collectionBehavior.contains(
                .moveToActiveSpace
            )
        )
        XCTAssertTrue(
            MoraeSettingsWindowController.collectionBehavior.contains(
                .fullScreenAuxiliary
            )
        )
    }

    func testDetailedNotificationCopyIsBoundedAndExplicitlyOptIn() {
        let instant = Date(unixMilliseconds: 1_800_000_000_000)
        let run = AgentRun(
            id: AgentRunID(rawValue: UUID()),
            source: .codex,
            sessionID: "session",
            turnID: "turn",
            title: String(repeating: "제", count: 140),
            status: .completed,
            receivedAt: instant,
            updatedAt: instant,
            lastMessage: String(repeating: "내", count: 260)
        )

        XCTAssertEqual(
            SystemAgentNotifier.title(for: run),
            "Codex 작업이 완료됐어요."
        )
        XCTAssertEqual(
            SystemAgentNotifier.title(for: run, showDetails: true).count,
            120
        )
        XCTAssertEqual(
            SystemAgentNotifier.body(for: run, showDetails: true).count,
            240
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
