import Foundation
import MoraeCore
import Security

enum JiraIntegrationError: Error, Equatable, LocalizedError, Sendable {
    case invalidSiteURL
    case cloudSiteRequired
    case authenticationFailed
    case forbidden
    case rateLimited
    case serverUnavailable
    case invalidResponse
    case responseTooLarge
    case tooManyIssues
    case missingCredential
    case keychainFailure(Int32)
    case ambiguousStartDateFields([JiraFieldDefinition])
    case invalidStartDateField
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidSiteURL:
            "https://로 시작하는 Jira 사이트 주소를 확인해 주세요."
        case .cloudSiteRequired:
            "현재 버전은 Jira Cloud만 지원합니다."
        case .authenticationFailed:
            "이메일 또는 API 토큰이 올바르지 않습니다."
        case .forbidden:
            "Jira 이슈를 조회할 권한이 없습니다."
        case .rateLimited:
            "Jira 요청 한도를 초과했습니다. 잠시 후 직접 다시 시도해 주세요."
        case .serverUnavailable:
            "Jira 서버에 연결할 수 없습니다."
        case .invalidResponse:
            "Jira 응답 형식을 읽을 수 없습니다."
        case .responseTooLarge:
            "Jira 응답이 안전한 처리 크기를 초과했습니다."
        case .tooManyIssues:
            "가져올 Jira 이슈가 200개를 초과했습니다. Jira에서 범위를 정리한 뒤 다시 시도해 주세요."
        case .missingCredential:
            "저장된 Jira API 토큰을 찾을 수 없습니다. 다시 연결해 주세요."
        case let .keychainFailure(status):
            "API 토큰을 Keychain에서 처리하지 못했습니다. (\(status))"
        case .ambiguousStartDateFields:
            "시작 날짜 필드가 여러 개입니다. 사용할 필드를 선택해 주세요."
        case .invalidStartDateField:
            "선택한 Jira 시작 날짜 필드를 사용할 수 없습니다."
        case .notConnected:
            "먼저 Jira를 연결해 주세요."
        }
    }
}

struct JiraFieldDefinition: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let untranslatedName: String?
    let isCustom: Bool
    let isSearchable: Bool
    let schemaType: String?

    var displayName: String {
        untranslatedName?.nilIfBlank ?? name
    }
}

enum JiraStartDateFieldResolver {
    static func candidates(
        from fields: [JiraFieldDefinition]
    ) -> [JiraFieldDefinition] {
        fields.filter {
            $0.isCustom
                && $0.isSearchable
                && $0.schemaType?.lowercased() == "date"
                && [$0.name, $0.untranslatedName]
                    .compactMap { $0?.lowercased() }
                    .contains("start date")
                && numericCustomFieldID($0.id) != nil
        }
    }

    static func resolve(
        fields: [JiraFieldDefinition],
        preferredID: String?
    ) throws -> String? {
        let matches = candidates(from: fields)
        if let preferredID {
            guard matches.contains(where: { $0.id == preferredID }) else {
                throw JiraIntegrationError.invalidStartDateField
            }
            return preferredID
        }
        switch matches.count {
        case 0:
            return nil
        case 1:
            return matches[0].id
        default:
            throw JiraIntegrationError.ambiguousStartDateFields(matches)
        }
    }

    static func numericCustomFieldID(_ value: String) -> String? {
        let prefix = "customfield_"
        guard value.hasPrefix(prefix) else { return nil }
        let number = String(value.dropFirst(prefix.count))
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else {
            return nil
        }
        return number
    }
}

enum JiraCandidateQueryBuilder {
    static func build(
        day: LocalDay,
        startDateFieldID: String?
    ) throws -> String {
        var dateConditions = [
            #"statusCategory = "In Progress""#,
            #"due <= "\#(day.rawValue)""#,
        ]
        if let startDateFieldID {
            guard let numericID =
                    JiraStartDateFieldResolver.numericCustomFieldID(
                        startDateFieldID
                    )
            else {
                throw JiraIntegrationError.invalidStartDateField
            }
            dateConditions.insert(
                #"cf[\#(numericID)] <= "\#(day.rawValue)""#,
                at: 1
            )
        }
        return """
            assignee = currentUser()
            AND statusCategory != Done
            AND issuetype NOT IN ("Epic", "Initiative")
            AND status NOT IN ("Hold", "Backlog")
            AND (
              \(dateConditions.joined(separator: "\n  OR "))
            )
            ORDER BY priority DESC, updated DESC
            """
    }
}

struct JiraConnection: Equatable, Sendable {
    let inputSiteURL: URL
    let apiBaseURL: URL
    let displayBaseURL: URL
    let accountEmail: String
    let startDateFieldID: String?
    let isEnabled: Bool
}

struct JiraIntegrationSnapshot: Equatable, Sendable {
    let connection: JiraConnection?
    let lastAutomaticAttemptDay: LocalDay?
    let lastSuccessfulSyncAt: Date?
}

enum JiraConnectResult: Equatable, Sendable {
    case connected(JiraConnection)
    case requiresStartDateFieldSelection([JiraFieldDefinition])
}

enum JiraSyncMode: Equatable, Sendable {
    case automatic
    case manual
}

struct JiraSyncResult: Equatable, Sendable {
    let importedCount: Int
    let refreshedCount: Int
    let skippedBecauseAlreadyAttempted: Bool

    static let alreadyAttempted = JiraSyncResult(
        importedCount: 0,
        refreshedCount: 0,
        skippedBecauseAlreadyAttempted: true
    )
}

struct JiraIssueSnapshot: Equatable, Sendable {
    let issueID: String
    let issueKey: String
    let summary: String
    let statusCategory: String
    let statusName: String
    let startDay: LocalDay?
    let dueDay: LocalDay?
}

protocol JiraConnectionStoring: Sendable {
    func snapshot() -> JiraIntegrationSnapshot
    func save(connection: JiraConnection)
    func clear()
    func claimAutomaticAttempt(day: LocalDay) -> Bool
    func recordSuccessfulSync(at date: Date)
}

final class UserDefaultsJiraConnectionStore:
    JiraConnectionStoring,
    @unchecked Sendable
{
    private enum Key {
        static let enabled = "jira.isEnabled"
        static let inputSiteURL = "jira.inputSiteURL"
        static let apiBaseURL = "jira.apiBaseURL"
        static let displayBaseURL = "jira.displayBaseURL"
        static let accountEmail = "jira.accountEmail"
        static let startDateFieldID = "jira.startDateFieldID"
        static let lastAutomaticAttemptDay = "jira.lastAutomaticAttemptDay"
        static let lastSuccessfulSyncAtMs = "jira.lastSuccessfulSyncAtMs"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot() -> JiraIntegrationSnapshot {
        lock.withLock {
            JiraIntegrationSnapshot(
                connection: loadConnection(),
                lastAutomaticAttemptDay: defaults
                    .string(forKey: Key.lastAutomaticAttemptDay)
                    .flatMap { try? LocalDay(rawValue: $0) },
                lastSuccessfulSyncAt: {
                    guard defaults.object(
                        forKey: Key.lastSuccessfulSyncAtMs
                    ) != nil else {
                        return nil
                    }
                    return Date(
                        unixMilliseconds: Int64(
                            defaults.double(
                                forKey: Key.lastSuccessfulSyncAtMs
                            )
                        )
                    )
                }()
            )
        }
    }

    func save(connection: JiraConnection) {
        lock.withLock {
            defaults.set(connection.isEnabled, forKey: Key.enabled)
            defaults.set(
                connection.inputSiteURL.absoluteString,
                forKey: Key.inputSiteURL
            )
            defaults.set(
                connection.apiBaseURL.absoluteString,
                forKey: Key.apiBaseURL
            )
            defaults.set(
                connection.displayBaseURL.absoluteString,
                forKey: Key.displayBaseURL
            )
            defaults.set(connection.accountEmail, forKey: Key.accountEmail)
            defaults.set(
                connection.startDateFieldID,
                forKey: Key.startDateFieldID
            )
        }
    }

    func clear() {
        lock.withLock {
            [
                Key.enabled,
                Key.inputSiteURL,
                Key.apiBaseURL,
                Key.displayBaseURL,
                Key.accountEmail,
                Key.startDateFieldID,
                Key.lastAutomaticAttemptDay,
                Key.lastSuccessfulSyncAtMs,
            ].forEach(defaults.removeObject(forKey:))
        }
    }

    func claimAutomaticAttempt(day: LocalDay) -> Bool {
        lock.withLock {
            guard defaults.string(forKey: Key.lastAutomaticAttemptDay)
                    != day.rawValue else {
                return false
            }
            defaults.set(day.rawValue, forKey: Key.lastAutomaticAttemptDay)
            return true
        }
    }

    func recordSuccessfulSync(at date: Date) {
        lock.withLock {
            defaults.set(
                date.unixMilliseconds,
                forKey: Key.lastSuccessfulSyncAtMs
            )
        }
    }

    private func loadConnection() -> JiraConnection? {
        guard defaults.bool(forKey: Key.enabled),
              let input = defaults.string(forKey: Key.inputSiteURL)
                .flatMap(URL.init(string:)),
              let api = defaults.string(forKey: Key.apiBaseURL)
                .flatMap(URL.init(string:)),
              let display = defaults.string(forKey: Key.displayBaseURL)
                .flatMap(URL.init(string:)),
              let email = defaults.string(forKey: Key.accountEmail)?
                .nilIfBlank else {
            return nil
        }
        return JiraConnection(
            inputSiteURL: input,
            apiBaseURL: api,
            displayBaseURL: display,
            accountEmail: email,
            startDateFieldID: defaults.string(
                forKey: Key.startDateFieldID
            )?.nilIfBlank,
            isEnabled: true
        )
    }
}

protocol JiraCredentialStoring: Sendable {
    func save(token: String, accountEmail: String) throws
    func load(accountEmail: String) throws -> String?
    func delete(accountEmail: String) throws
}

final class InMemoryJiraCredentialStore:
    JiraCredentialStoring,
    @unchecked Sendable
{
    private var tokens: [String: String] = [:]
    private let lock = NSLock()

    func save(token: String, accountEmail: String) throws {
        lock.withLock {
            tokens[accountEmail] = token
        }
    }

    func load(accountEmail: String) throws -> String? {
        lock.withLock {
            tokens[accountEmail]
        }
    }

    func delete(accountEmail: String) throws {
        _ = lock.withLock {
            tokens.removeValue(forKey: accountEmail)
        }
    }
}

struct KeychainJiraCredentialStore: JiraCredentialStoring {
    static let service = "io.github.heejung-29cm.morae.jira"

    func save(token: String, accountEmail: String) throws {
        let tokenData = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountEmail,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw JiraIntegrationError.keychainFailure(updateStatus)
        }
        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw JiraIntegrationError.keychainFailure(addStatus)
        }
    }

    func load(accountEmail: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountEmail,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw JiraIntegrationError.keychainFailure(status)
        }
        return token
    }

    func delete(accountEmail: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountEmail,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JiraIntegrationError.keychainFailure(status)
        }
    }
}

struct JiraSiteInfo: Equatable, Sendable {
    let apiBaseURL: URL
    let displayBaseURL: URL
    let deploymentType: String
}

protocol JiraClient: Sendable {
    func discoverSite(inputURL: URL) async throws -> JiraSiteInfo
    func validateAccount(
        baseURL: URL,
        email: String,
        token: String
    ) async throws
    func fields(
        baseURL: URL,
        email: String,
        token: String
    ) async throws -> [JiraFieldDefinition]
    func search(
        baseURL: URL,
        email: String,
        token: String,
        day: LocalDay,
        startDateFieldID: String?
    ) async throws -> [JiraIssueSnapshot]
}

struct LiveJiraClient: JiraClient {
    private static let responseLimit = 2 * 1_024 * 1_024
    private static let issueLimit = 200

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 10
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func discoverSite(inputURL: URL) async throws -> JiraSiteInfo {
        let normalized = try Self.normalizedHTTPSBaseURL(inputURL)
        let request = URLRequest(
            url: Self.endpoint(
                baseURL: normalized,
                path: "/rest/api/3/serverInfo"
            )
        )
        let response: JiraServerInfoDTO = try await send(
            request,
            authenticated: false
        )
        guard let apiBaseURL = URL(string: response.baseUrl),
              let displayBaseURL = URL(string: response.displayUrl),
              Self.isCanonicalCloudAPIURL(apiBaseURL),
              displayBaseURL.scheme?.lowercased() == "https",
              displayBaseURL.host != nil,
              displayBaseURL.user == nil,
              displayBaseURL.password == nil else {
            throw JiraIntegrationError.invalidResponse
        }
        return JiraSiteInfo(
            apiBaseURL: apiBaseURL,
            displayBaseURL: displayBaseURL,
            deploymentType: response.deploymentType
        )
    }

    func validateAccount(
        baseURL: URL,
        email: String,
        token: String
    ) async throws {
        var request = URLRequest(
            url: Self.endpoint(
                baseURL: baseURL,
                path: "/rest/api/3/myself"
            )
        )
        Self.authenticate(&request, email: email, token: token)
        let _: JiraMyselfDTO = try await send(
            request,
            authenticated: true
        )
    }

    func fields(
        baseURL: URL,
        email: String,
        token: String
    ) async throws -> [JiraFieldDefinition] {
        var request = URLRequest(
            url: Self.endpoint(
                baseURL: baseURL,
                path: "/rest/api/3/field"
            )
        )
        Self.authenticate(&request, email: email, token: token)
        let fields: [JiraFieldDTO] = try await send(
            request,
            authenticated: true
        )
        return fields.map(\.definition)
    }

    func search(
        baseURL: URL,
        email: String,
        token: String,
        day: LocalDay,
        startDateFieldID: String?
    ) async throws -> [JiraIssueSnapshot] {
        let jql = try JiraCandidateQueryBuilder.build(
            day: day,
            startDateFieldID: startDateFieldID
        )
        var issues: [JiraIssueSnapshot] = []
        var receivedIssueCount = 0
        var nextPageToken: String?
        repeat {
            var request = URLRequest(
                url: Self.endpoint(
                    baseURL: baseURL,
                    path: "/rest/api/3/search/jql"
                )
            )
            request.httpMethod = "POST"
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            Self.authenticate(&request, email: email, token: token)
            request.httpBody = try JSONEncoder().encode(
                JiraSearchRequestDTO(
                    jql: jql,
                    fields: [
                        "summary",
                        "status",
                        "issuetype",
                        "duedate",
                        "updated",
                    ] + (startDateFieldID.map { [$0] } ?? []),
                    maxResults: min(50, Self.issueLimit - issues.count),
                    nextPageToken: nextPageToken
                )
            )
            let page: JiraSearchResponseDTO = try await send(
                request,
                authenticated: true
            )
            receivedIssueCount += page.issues.count
            issues.append(
                contentsOf: page.issues.compactMap {
                    $0.snapshot(startDateFieldID: startDateFieldID)
                }
            )
            nextPageToken = page.nextPageToken?.nilIfBlank
            if nextPageToken != nil,
               receivedIssueCount >= Self.issueLimit {
                throw JiraIntegrationError.tooManyIssues
            }
        } while nextPageToken != nil
        return Self.sortedCandidates(issues, day: day)
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        authenticated: Bool
    ) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JiraIntegrationError.invalidResponse
            }
            guard data.count <= Self.responseLimit else {
                throw JiraIntegrationError.responseTooLarge
            }
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 401:
                throw JiraIntegrationError.authenticationFailed
            case 403:
                throw JiraIntegrationError.forbidden
            case 429:
                throw JiraIntegrationError.rateLimited
            case 500...599:
                throw JiraIntegrationError.serverUnavailable
            default:
                throw authenticated
                    ? JiraIntegrationError.invalidResponse
                    : JiraIntegrationError.invalidSiteURL
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw JiraIntegrationError.invalidResponse
            }
        } catch let error as JiraIntegrationError {
            throw error
        } catch {
            throw JiraIntegrationError.serverUnavailable
        }
    }

    private static func authenticate(
        _ request: inout URLRequest,
        email: String,
        token: String
    ) {
        let value = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue(
            "Basic \(value)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private static func normalizedHTTPSBaseURL(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            throw JiraIntegrationError.invalidSiteURL
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        components?.path = ""
        guard let normalized = components?.url else {
            throw JiraIntegrationError.invalidSiteURL
        }
        return normalized
    }

    private static func isCanonicalCloudAPIURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host.hasSuffix(".atlassian.net"),
              url.user == nil,
              url.password == nil else {
            return false
        }
        return true
    }

    private static func sortedCandidates(
        _ issues: [JiraIssueSnapshot],
        day: LocalDay
    ) -> [JiraIssueSnapshot] {
        issues.enumerated().sorted { lhs, rhs in
            let lhsRank = candidateRank(lhs.element, day: day)
            let rhsRank = candidateRank(rhs.element, day: day)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhsRank == 1,
               let lhsDue = lhs.element.dueDay,
               let rhsDue = rhs.element.dueDay,
               lhsDue != rhsDue {
                return lhsDue < rhsDue
            }
            if lhsRank == 2,
               let lhsStart = lhs.element.startDay,
               let rhsStart = rhs.element.startDay,
               lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
            if lhs.offset != rhs.offset {
                return lhs.offset < rhs.offset
            }
            return lhs.element.issueKey < rhs.element.issueKey
        }
        .map(\.element)
    }

    private static func candidateRank(
        _ issue: JiraIssueSnapshot,
        day: LocalDay
    ) -> Int {
        let statusCategory = issue.statusCategory.lowercased()
        if statusCategory == "indeterminate"
            || statusCategory == "in progress" {
            return 0
        }
        if let dueDay = issue.dueDay, dueDay < day {
            return 1
        }
        if let startDay = issue.startDay, startDay <= day {
            return 2
        }
        return 3
    }

    private static func endpoint(baseURL: URL, path: String) -> URL {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.query = nil
        components.fragment = nil
        components.path =
            components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .isEmpty
            ? path
            : "/"
                + components.path.trimmingCharacters(
                    in: CharacterSet(charactersIn: "/")
                )
                + path
        return components.url!
    }
}

actor JiraIntegrationService {
    private let connectionStore: any JiraConnectionStoring
    private let credentialStore: any JiraCredentialStoring
    private let client: any JiraClient
    private let todoRepository: any TodoRepository
    private let clock: any Clock
    private let uuidGenerator: any UUIDGenerating

    init(
        connectionStore: any JiraConnectionStoring,
        credentialStore: any JiraCredentialStoring,
        client: any JiraClient,
        todoRepository: any TodoRepository,
        clock: any Clock,
        uuidGenerator: any UUIDGenerating
    ) {
        self.connectionStore = connectionStore
        self.credentialStore = credentialStore
        self.client = client
        self.todoRepository = todoRepository
        self.clock = clock
        self.uuidGenerator = uuidGenerator
    }

    func snapshot() -> JiraIntegrationSnapshot {
        connectionStore.snapshot()
    }

    func connect(
        siteURLText: String,
        accountEmail: String,
        token: String,
        preferredStartDateFieldID: String? = nil
    ) async throws -> JiraConnectResult {
        let siteText = siteURLText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let email = accountEmail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedToken = token.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let inputURL = URL(string: siteText),
              inputURL.scheme?.lowercased() == "https",
              !email.isEmpty,
              !normalizedToken.isEmpty else {
            throw JiraIntegrationError.invalidSiteURL
        }

        let site = try await client.discoverSite(inputURL: inputURL)
        guard site.deploymentType.caseInsensitiveCompare("Cloud")
                == .orderedSame else {
            throw JiraIntegrationError.cloudSiteRequired
        }
        try await client.validateAccount(
            baseURL: site.apiBaseURL,
            email: email,
            token: normalizedToken
        )
        let fields = try await client.fields(
            baseURL: site.apiBaseURL,
            email: email,
            token: normalizedToken
        )
        let startDateFieldID: String?
        do {
            startDateFieldID = try JiraStartDateFieldResolver.resolve(
                fields: fields,
                preferredID: preferredStartDateFieldID
            )
        } catch let JiraIntegrationError.ambiguousStartDateFields(candidates) {
            return .requiresStartDateFieldSelection(candidates)
        }

        let previousConnection = connectionStore.snapshot().connection
        try credentialStore.save(
            token: normalizedToken,
            accountEmail: email
        )
        let connection = JiraConnection(
            inputSiteURL: inputURL,
            apiBaseURL: site.apiBaseURL,
            displayBaseURL: site.displayBaseURL,
            accountEmail: email,
            startDateFieldID: startDateFieldID,
            isEnabled: true
        )
        connectionStore.save(connection: connection)
        if let previousConnection,
           previousConnection.accountEmail != email {
            try? credentialStore.delete(
                accountEmail: previousConnection.accountEmail
            )
        }
        return .connected(connection)
    }

    func disconnect() throws {
        if let connection = connectionStore.snapshot().connection {
            try credentialStore.delete(
                accountEmail: connection.accountEmail
            )
        }
        connectionStore.clear()
    }

    func sync(
        day: LocalDay,
        mode: JiraSyncMode
    ) async throws -> JiraSyncResult {
        guard let connection = connectionStore.snapshot().connection else {
            throw JiraIntegrationError.notConnected
        }
        if mode == .automatic,
           !connectionStore.claimAutomaticAttempt(day: day) {
            return .alreadyAttempted
        }
        guard let token = try credentialStore.load(
            accountEmail: connection.accountEmail
        ) else {
            throw JiraIntegrationError.missingCredential
        }
        let issues = try await client.search(
            baseURL: connection.apiBaseURL,
            email: connection.accountEmail,
            token: token,
            day: day,
            startDateFieldID: connection.startDateFieldID
        )
        let now = clock.now()
        let result = try await todoRepository.importJira(
            issues,
            day: day,
            displayBaseURL: connection.displayBaseURL,
            newIDs: issues.map { _ in
                TodoID(rawValue: uuidGenerator.next())
            },
            at: now
        )
        connectionStore.recordSuccessfulSync(at: now)
        return JiraSyncResult(
            importedCount: result.importedCount,
            refreshedCount: result.refreshedCount,
            skippedBecauseAlreadyAttempted: false
        )
    }
}

private struct JiraServerInfoDTO: Decodable {
    let baseUrl: String
    let displayUrl: String
    let deploymentType: String
}

private struct JiraMyselfDTO: Decodable {
    let accountId: String
}

private struct JiraFieldDTO: Decodable {
    let id: String
    let name: String
    let untranslatedName: String?
    let custom: Bool?
    let searchable: Bool?
    let schema: JiraFieldSchemaDTO?

    var definition: JiraFieldDefinition {
        JiraFieldDefinition(
            id: id,
            name: name,
            untranslatedName: untranslatedName,
            isCustom: custom ?? id.hasPrefix("customfield_"),
            isSearchable: searchable ?? true,
            schemaType: schema?.type
        )
    }
}

private struct JiraFieldSchemaDTO: Decodable {
    let type: String?
}

private struct JiraSearchRequestDTO: Encodable {
    let jql: String
    let fields: [String]
    let maxResults: Int
    let nextPageToken: String?
}

private struct JiraSearchResponseDTO: Decodable {
    let issues: [JiraIssueDTO]
    let nextPageToken: String?
}

private struct JiraIssueDTO: Decodable {
    let id: String
    let key: String
    let fields: JiraIssueFieldsDTO

    func snapshot(startDateFieldID: String?) -> JiraIssueSnapshot? {
        guard let summary = fields.summary?.nilIfBlank,
              let status = fields.status else {
            return nil
        }
        let excludedStatuses = Set(["hold", "backlog"])
        guard !excludedStatuses.contains(
            status.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
        ) else {
            return nil
        }
        if let issueType = fields.issueType {
            let normalizedType = issueType.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
            guard !Set(["epic", "initiative"]).contains(normalizedType),
                  issueType.hierarchyLevel != 1 else {
                return nil
            }
        }
        return JiraIssueSnapshot(
            issueID: id,
            issueKey: key,
            summary: summary,
            statusCategory: status.statusCategory.key,
            statusName: status.name,
            startDay: startDateFieldID
                .flatMap { fields.customDateValues[$0] }
                .flatMap { try? LocalDay(rawValue: $0) },
            dueDay: fields.dueDate.flatMap {
                try? LocalDay(rawValue: $0)
            }
        )
    }
}

private struct JiraIssueFieldsDTO: Decodable {
    let summary: String?
    let status: JiraStatusDTO?
    let issueType: JiraIssueTypeDTO?
    let dueDate: String?
    let customDateValues: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: JiraDynamicCodingKey.self
        )
        summary = try container.decodeIfPresent(
            String.self,
            forKey: JiraDynamicCodingKey("summary")
        )
        status = try container.decodeIfPresent(
            JiraStatusDTO.self,
            forKey: JiraDynamicCodingKey("status")
        )
        issueType = try container.decodeIfPresent(
            JiraIssueTypeDTO.self,
            forKey: JiraDynamicCodingKey("issuetype")
        )
        dueDate = try container.decodeIfPresent(
            String.self,
            forKey: JiraDynamicCodingKey("duedate")
        )
        customDateValues = try container.allKeys.reduce(into: [:]) {
            values,
            key in
            guard key.stringValue.hasPrefix("customfield_"),
                  let value = try container.decodeIfPresent(
                    String.self,
                    forKey: key
                  ) else {
                return
            }
            values[key.stringValue] = value
        }
    }
}

private struct JiraStatusDTO: Decodable {
    let name: String
    let statusCategory: JiraStatusCategoryDTO
}

private struct JiraIssueTypeDTO: Decodable {
    let name: String
    let hierarchyLevel: Int?
}

private struct JiraStatusCategoryDTO: Decodable {
    let key: String
}

private struct JiraDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
