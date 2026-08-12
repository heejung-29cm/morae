import MoraeCore
@testable import MoraeApp
import XCTest

final class JiraFeatureTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testSiteDiscoverySeparatesDisplayAndCanonicalAPIURL() async throws {
        StubURLProtocol.register { request in
            XCTAssertEqual(
                request.url?.path,
                "/rest/api/3/serverInfo"
            )
            XCTAssertNil(
                request.value(forHTTPHeaderField: "Authorization")
            )
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "baseUrl": "https://example.atlassian.net",
                      "displayUrl": "https://jira.example.com",
                      "deploymentType": "Cloud"
                    }
                    """.utf8
                )
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = LiveJiraClient(
            session: URLSession(configuration: configuration)
        )

        let site = try await client.discoverSite(
            inputURL: URL(string: "https://jira.example.com/browse/TEAM-1")!
        )

        XCTAssertEqual(
            site.apiBaseURL,
            URL(string: "https://example.atlassian.net")
        )
        XCTAssertEqual(
            site.displayBaseURL,
            URL(string: "https://jira.example.com")
        )
    }

    func testSiteDiscoveryRejectsNonAtlassianCredentialDestination()
        async
    {
        StubURLProtocol.register { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "baseUrl": "https://credential-thief.example",
                      "displayUrl": "https://jira.example.com",
                      "deploymentType": "Cloud"
                    }
                    """.utf8
                )
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = LiveJiraClient(
            session: URLSession(configuration: configuration)
        )

        await XCTAssertThrowsErrorAsync(
            try await client.discoverSite(
                inputURL: URL(string: "https://jira.example.com")!
            )
        ) { error in
            XCTAssertEqual(
                error as? JiraIntegrationError,
                .invalidResponse
            )
        }
    }

    func testCandidateQueryIncludesRequiredEligibilityRules() throws {
        let day = try LocalDay(rawValue: "2026-07-31")

        let jql = try JiraCandidateQueryBuilder.build(
            day: day,
            startDateFieldID: "customfield_10015"
        )

        XCTAssertTrue(jql.contains("assignee = currentUser()"))
        XCTAssertTrue(jql.contains("statusCategory != Done"))
        XCTAssertTrue(
            jql.contains(
                #"issuetype NOT IN ("Epic", "Initiative")"#
            )
        )
        XCTAssertTrue(
            jql.contains(#"status NOT IN ("Hold", "Backlog")"#)
        )
        XCTAssertTrue(jql.contains(#"statusCategory = "In Progress""#))
        XCTAssertTrue(jql.contains(#"cf[10015] <= "2026-07-31""#))
        XCTAssertTrue(jql.contains(#"due <= "2026-07-31""#))
    }

    func testCandidateQueryRejectsUnsafeCustomFieldID() throws {
        let day = try LocalDay(rawValue: "2026-07-31")

        XCTAssertThrowsError(
            try JiraCandidateQueryBuilder.build(
                day: day,
                startDateFieldID: #"customfield_1) OR assignee IS NOT EMPTY"#
            )
        ) { error in
            XCTAssertEqual(
                error as? JiraIntegrationError,
                .invalidStartDateField
            )
        }
    }

    func testStartDateResolverUsesSearchableDateField() throws {
        let fields = [
            JiraFieldDefinition(
                id: "customfield_10010",
                name: "Start date",
                untranslatedName: "Start date",
                isCustom: true,
                isSearchable: true,
                schemaType: "date"
            ),
            JiraFieldDefinition(
                id: "customfield_10011",
                name: "Start date",
                untranslatedName: "Start date",
                isCustom: true,
                isSearchable: true,
                schemaType: "string"
            ),
        ]

        XCTAssertEqual(
            try JiraStartDateFieldResolver.resolve(
                fields: fields,
                preferredID: nil
            ),
            "customfield_10010"
        )
    }

    func testSearchDefensivelyExcludesParentAndPausedWork() async throws {
        StubURLProtocol.register { request in
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "issues": [
                        {
                          "id": "1",
                          "key": "TEAM-1",
                          "fields": {
                            "summary": "Normal task",
                            "status": {
                              "name": "In Progress",
                              "statusCategory": {"key": "indeterminate"}
                            },
                            "issuetype": {
                              "name": "Task",
                              "hierarchyLevel": 0
                            }
                          }
                        },
                        {
                          "id": "2",
                          "key": "TEAM-2",
                          "fields": {
                            "summary": "Epic",
                            "status": {
                              "name": "In Progress",
                              "statusCategory": {"key": "indeterminate"}
                            },
                            "issuetype": {
                              "name": "Epic",
                              "hierarchyLevel": 1
                            }
                          }
                        },
                        {
                          "id": "3",
                          "key": "TEAM-3",
                          "fields": {
                            "summary": "Initiative",
                            "status": {
                              "name": "In Progress",
                              "statusCategory": {"key": "indeterminate"}
                            },
                            "issuetype": {
                              "name": "Initiative",
                              "hierarchyLevel": 2
                            }
                          }
                        },
                        {
                          "id": "4",
                          "key": "TEAM-4",
                          "fields": {
                            "summary": "Held",
                            "status": {
                              "name": "Hold",
                              "statusCategory": {"key": "indeterminate"}
                            },
                            "issuetype": {
                              "name": "Task",
                              "hierarchyLevel": 0
                            }
                          }
                        },
                        {
                          "id": "5",
                          "key": "TEAM-5",
                          "fields": {
                            "summary": "Backlog",
                            "status": {
                              "name": "Backlog",
                              "statusCategory": {"key": "new"}
                            },
                            "issuetype": {
                              "name": "Task",
                              "hierarchyLevel": 0
                            }
                          }
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = LiveJiraClient(
            session: URLSession(configuration: configuration)
        )

        let issues = try await client.search(
            baseURL: URL(string: "https://example.atlassian.net")!,
            email: "user@example.com",
            token: "token",
            day: try LocalDay(rawValue: "2026-07-31"),
            startDateFieldID: nil
        )

        XCTAssertEqual(issues.map(\.issueKey), ["TEAM-1"])
    }

    func testAutomaticAttemptIsClaimedOnlyOncePerDay() throws {
        let suite = "JiraFeatureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsJiraConnectionStore(defaults: defaults)
        let firstDay = try LocalDay(rawValue: "2026-07-31")
        let nextDay = try LocalDay(rawValue: "2026-08-01")

        XCTAssertTrue(store.claimAutomaticAttempt(day: firstDay))
        XCTAssertFalse(store.claimAutomaticAttempt(day: firstDay))
        XCTAssertTrue(store.claimAutomaticAttempt(day: nextDay))
    }

    func testJiraImportIsIdempotentAndPreservesLocalCompletion() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-31")
        let now = Date(unixMilliseconds: 1_775_039_000_000)
        let firstID = TodoID(rawValue: UUID())
        let issue = JiraIssueSnapshot(
            issueID: "10001",
            issueKey: "TEAM-1",
            summary: "First summary",
            statusCategory: "indeterminate",
            statusName: "In Progress",
            startDay: try LocalDay(rawValue: "2026-07-30"),
            dueDay: try LocalDay(rawValue: "2026-07-31")
        )

        let first = try await repository.importJira(
            [issue],
            day: day,
            displayBaseURL: URL(string: "https://team.example.com")!,
            newIDs: [firstID],
            at: now
        )
        _ = try await repository.setCompletion(
            id: firstID,
            isCompleted: true,
            at: now.addingTimeInterval(60)
        )

        let refreshedIssue = JiraIssueSnapshot(
            issueID: issue.issueID,
            issueKey: issue.issueKey,
            summary: "Updated summary",
            statusCategory: "new",
            statusName: "To Do",
            startDay: issue.startDay,
            dueDay: issue.dueDay
        )
        let second = try await repository.importJira(
            [refreshedIssue],
            day: day,
            displayBaseURL: URL(string: "https://team.example.com")!,
            newIDs: [TodoID(rawValue: UUID())],
            at: now.addingTimeInterval(120)
        )
        let storedItems = try await repository.list(day: day)
        let stored = try XCTUnwrap(storedItems.first)

        XCTAssertEqual(first.importedCount, 1)
        XCTAssertEqual(second.importedCount, 0)
        XCTAssertEqual(second.refreshedCount, 1)
        XCTAssertEqual(stored.id, firstID)
        XCTAssertEqual(stored.title, "Updated summary")
        XCTAssertEqual(stored.status, .completed)
        XCTAssertTrue(stored.origin.isJira)
    }

    func testJiraItemsAreExcludedFromCarryOverAndRepeatOnNextDay()
        async throws
    {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-31")
        let nextDay = try LocalDay(rawValue: "2026-08-01")
        let issue = JiraIssueSnapshot(
            issueID: "10002",
            issueKey: "TEAM-2",
            summary: "Still active",
            statusCategory: "indeterminate",
            statusName: "In Progress",
            startDay: day,
            dueDay: nil
        )

        _ = try await repository.importJira(
            [issue],
            day: day,
            displayBaseURL: URL(string: "https://team.example.com")!,
            newIDs: [TodoID(rawValue: UUID())],
            at: Date(unixMilliseconds: 1_775_039_000_000)
        )
        let carryOver = try await repository.listCarryOverCandidates(
            from: day,
            to: nextDay
        )
        _ = try await repository.importJira(
            [issue],
            day: nextDay,
            displayBaseURL: URL(string: "https://team.example.com")!,
            newIDs: [TodoID(rawValue: UUID())],
            at: Date(unixMilliseconds: 1_775_125_400_000)
        )

        let firstDayItems = try await repository.list(day: day)
        let nextDayItems = try await repository.list(day: nextDay)

        XCTAssertTrue(carryOver.isEmpty)
        XCTAssertEqual(firstDayItems.count, 1)
        XCTAssertEqual(nextDayItems.count, 1)
    }

    func testDeletedJiraItemStaysDismissedForDayAndUndoRestoresIt()
        async throws
    {
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let day = try LocalDay(rawValue: "2026-07-31")
        let now = Date(unixMilliseconds: 1_775_039_000_000)
        let issue = JiraIssueSnapshot(
            issueID: "10003",
            issueKey: "TEAM-3",
            summary: "Dismiss locally",
            statusCategory: "indeterminate",
            statusName: "In Progress",
            startDay: day,
            dueDay: nil
        )

        _ = try await repository.importJira(
            [issue],
            day: day,
            displayBaseURL: URL(string: "https://team.example.com")!,
            newIDs: [TodoID(rawValue: UUID())],
            at: now
        )
        let initiallyStored = try await repository.list(day: day)
        let imported = try XCTUnwrap(initiallyStored.first)
        try await repository.delete(id: imported.id)

        let repeated = try await repository.importJira(
            [issue],
            day: day,
            displayBaseURL: URL(string: "https://team.example.com")!,
            newIDs: [TodoID(rawValue: UUID())],
            at: now.addingTimeInterval(60)
        )

        let afterRepeatedImport = try await repository.list(day: day)
        XCTAssertEqual(repeated.importedCount, 0)
        XCTAssertTrue(afterRepeatedImport.isEmpty)

        try await repository.insert(imported)
        let refreshed = try await repository.importJira(
            [issue],
            day: day,
            displayBaseURL: URL(string: "https://team.example.com")!,
            newIDs: [TodoID(rawValue: UUID())],
            at: now.addingTimeInterval(120)
        )

        let afterUndo = try await repository.list(day: day)
        XCTAssertEqual(refreshed.refreshedCount, 1)
        XCTAssertEqual(afterUndo.count, 1)
    }

    @MainActor
    func testMenuBarExposesConnectedJiraAndRunsManualSync() async throws {
        let suite = "JiraFeatureTests.MenuBar.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let connectionStore = UserDefaultsJiraConnectionStore(
            defaults: defaults
        )
        connectionStore.save(
            connection: JiraConnection(
                inputSiteURL: URL(string: "https://jira.example.com")!,
                apiBaseURL: URL(
                    string: "https://example.atlassian.net"
                )!,
                displayBaseURL: URL(string: "https://jira.example.com")!,
                accountEmail: "user@example.com",
                startDateFieldID: nil,
                isEnabled: true
            )
        )
        let database = try AppDatabase.inMemory()
        let repository = GRDBTodoRepository(database: database)
        let instant = Date(unixMilliseconds: 1_775_040_000_000)
        let issue = JiraIssueSnapshot(
            issueID: "30001",
            issueKey: "TEAM-30",
            summary: "Menu sync",
            statusCategory: "indeterminate",
            statusName: "In Progress",
            startDay: nil,
            dueDay: nil
        )
        let service = JiraIntegrationService(
            connectionStore: connectionStore,
            credentialStore: FixedJiraCredentialStore(token: "token"),
            client: FixedJiraClient(issues: [issue]),
            todoRepository: repository,
            clock: FixedClock(instant: instant),
            uuidGenerator: FixedUUIDGenerator(uuid: UUID())
        )
        let viewModel = MenuBarViewModel(
            repository: repository,
            clock: FixedClock(instant: instant),
            calendar: Calendar(identifier: .gregorian),
            jiraIntegration: service
        )

        await viewModel.onAppear()
        XCTAssertTrue(viewModel.isJiraConnected)
        XCTAssertFalse(viewModel.isJiraSyncing)

        await viewModel.syncJiraNow()

        XCTAssertFalse(viewModel.isJiraSyncing)
        XCTAssertEqual(
            viewModel.jiraSyncMessage,
            "새 Jira 항목 없이 1개를 확인했습니다."
        )
        XCTAssertEqual(viewModel.todayTodos.count, 1)
    }
}

private struct FixedJiraCredentialStore: JiraCredentialStoring {
    let token: String

    func save(token: String, accountEmail: String) throws {}

    func load(accountEmail: String) throws -> String? {
        token
    }

    func delete(accountEmail: String) throws {}
}

private struct FixedJiraClient: JiraClient {
    let issues: [JiraIssueSnapshot]

    func discoverSite(inputURL: URL) async throws -> JiraSiteInfo {
        JiraSiteInfo(
            apiBaseURL: inputURL,
            displayBaseURL: inputURL,
            deploymentType: "Cloud"
        )
    }

    func validateAccount(
        baseURL: URL,
        email: String,
        token: String
    ) async throws {}

    func fields(
        baseURL: URL,
        email: String,
        token: String
    ) async throws -> [JiraFieldDefinition] {
        []
    }

    func search(
        baseURL: URL,
        email: String,
        token: String,
        day: LocalDay,
        startDateFieldID: String?
    ) async throws -> [JiraIssueSnapshot] {
        issues
    }
}
