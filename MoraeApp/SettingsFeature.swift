import AppKit
import CoreFoundation
import Foundation
import MoraeCore
import Observation
import ServiceManagement

enum MoraeSettingKey {
    static let schemaVersion = "settings.schemaVersion"
    static let launchAtLogin = "settings.launchAtLogin"
    static let interests = "settings.interests"
    static let storeProjectPath = "privacy.storeProjectPath"
    static let storeAgentTitle = "privacy.storeAgentTitle"
    static let storeLastMessage = "privacy.storeLastMessage"
    static let showDetailsInNotification =
        "privacy.showDetailsInNotification"
}

struct MoraeSettings: Equatable, Sendable {
    static let schemaVersion = 1

    var storedSchemaVersion = schemaVersion
    var launchAtLogin = false
    var interests: [String] = []
    var storeProjectPath = false
    var storeAgentTitle = false
    var storeLastMessage = false
    var showDetailsInNotification = false

    var privacyPolicy: AgentPrivacyPolicy {
        AgentPrivacyPolicy(
            storeProjectPath: storeProjectPath,
            storeAgentTitle: storeAgentTitle,
            storeLastMessage: storeLastMessage,
            showDetailsInNotification: showDetailsInNotification
        )
    }
}

protocol SettingsStoring:
    AgentPrivacyPolicyProviding,
    BriefingPreferences,
    Sendable
{
    func load() -> MoraeSettings
    func save(_ settings: MoraeSettings)
}

final class UserDefaultsSettingsStore:
    SettingsStoring,
    @unchecked Sendable
{
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            MoraeSettingKey.schemaVersion: MoraeSettings.schemaVersion,
            MoraeSettingKey.launchAtLogin: false,
            MoraeSettingKey.interests: [String](),
            MoraeSettingKey.storeProjectPath: false,
            MoraeSettingKey.storeAgentTitle: false,
            MoraeSettingKey.storeLastMessage: false,
            MoraeSettingKey.showDetailsInNotification: false,
        ])
    }

    func load() -> MoraeSettings {
        MoraeSettings(
            storedSchemaVersion: safeSchemaVersion(),
            launchAtLogin: safeBool(MoraeSettingKey.launchAtLogin),
            interests: safeInterests(),
            storeProjectPath: safeBool(MoraeSettingKey.storeProjectPath),
            storeAgentTitle: safeBool(MoraeSettingKey.storeAgentTitle),
            storeLastMessage: safeBool(MoraeSettingKey.storeLastMessage),
            showDetailsInNotification: safeBool(
                MoraeSettingKey.showDetailsInNotification
            )
        )
    }

    func save(_ settings: MoraeSettings) {
        defaults.set(
            MoraeSettings.schemaVersion,
            forKey: MoraeSettingKey.schemaVersion
        )
        setBool(settings.launchAtLogin, forKey: MoraeSettingKey.launchAtLogin)
        defaults.set(settings.interests, forKey: MoraeSettingKey.interests)
        setBool(
            settings.storeProjectPath,
            forKey: MoraeSettingKey.storeProjectPath
        )
        setBool(
            settings.storeAgentTitle,
            forKey: MoraeSettingKey.storeAgentTitle
        )
        setBool(
            settings.storeLastMessage,
            forKey: MoraeSettingKey.storeLastMessage
        )
        setBool(
            settings.showDetailsInNotification,
            forKey: MoraeSettingKey.showDetailsInNotification
        )
    }

    func policy() -> AgentPrivacyPolicy {
        load().privacyPolicy
    }

    func interests() -> [String] {
        load().interests
    }

    private func safeBool(_ key: String) -> Bool {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return number.boolValue
    }

    private func setBool(_ value: Bool, forKey key: String) {
        // Replace malformed numeric/string values instead of allowing
        // UserDefaults' equality optimization to preserve their old type.
        defaults.removeObject(forKey: key)
        defaults.set(value, forKey: key)
    }

    private func safeSchemaVersion() -> Int {
        guard let number = defaults.object(
            forKey: MoraeSettingKey.schemaVersion
        ) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.intValue == MoraeSettings.schemaVersion else {
            return MoraeSettings.schemaVersion
        }
        return number.intValue
    }

    private func safeInterests() -> [String] {
        guard let values = defaults.object(
            forKey: MoraeSettingKey.interests
        ) as? [String] else {
            return []
        }
        var seen = Set<String>()
        return values.compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 40,
                  seen.insert(value.lowercased()).inserted else {
                return nil
            }
            return value
        }
        .prefix(20)
        .map(\.self)
    }
}

protocol LaunchAtLoginControlling: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

final class InMemoryLaunchAtLoginController:
    LaunchAtLoginControlling,
    @unchecked Sendable
{
    private var enabled = false
    private let lock = NSLock()

    func isEnabled() -> Bool {
        lock.withLock { enabled }
    }

    func setEnabled(_ enabled: Bool) throws {
        lock.withLock {
            self.enabled = enabled
        }
    }
}

struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum FeedManagementError: Error, Equatable, LocalizedError {
    case invalidHTTPSURL
    case duplicateURL
    case unreadableFeed

    var errorDescription: String? {
        switch self {
        case .invalidHTTPSURL:
            "https://로 시작하는 올바른 피드 URL을 입력해 주세요."
        case .duplicateURL:
            "이미 등록된 피드입니다."
        case .unreadableFeed:
            "RSS/Atom 피드를 읽을 수 없습니다. URL을 확인해 주세요."
        }
    }
}

protocol FeedValidating: Sendable {
    func validate(_ source: FeedSource) async throws
}

struct LiveFeedValidator: FeedValidating {
    let client: any FeedClient

    init(client: any FeedClient = LiveFeedClient()) {
        self.client = client
    }

    func validate(_ source: FeedSource) async throws {
        do {
            _ = try await client.candidates(from: source)
        } catch {
            throw FeedManagementError.unreadableFeed
        }
    }
}

enum HookSnippetBuilder {
    static func helperURL(bundle: Bundle = .main) -> URL {
        bundle.bundleURL
            .appendingPathComponent("Contents/MacOS/hamster-event")
    }

    static func codex(helperURL: URL) -> String {
        #"notify = ["\#(escaped(helperURL.path))"]"#
    }

    static func claude(helperURL: URL) -> String {
        func command(_ argument: String) -> String {
            let value = "\"\(helperURL.path)\" \(argument)"
            let data = try! JSONEncoder().encode(value)
            return String(decoding: data, as: UTF8.self)
        }
        return """
        {
          "hooks": {
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": \(command("claude-turn-start"))}]}],
            "Stop": [{"hooks": [{"type": "command", "command": \(command("claude-stop"))}]}],
            "Notification": [{"matcher": "permission_prompt|elicitation_dialog|agent_needs_input", "hooks": [{"type": "command", "command": \(command("claude-notification"))}]}],
            "TaskCompleted": [{"hooks": [{"type": "command", "command": \(command("claude-task-completed"))}]}],
            "StopFailure": [{"hooks": [{"type": "command", "command": \(command("claude-stop-failure"))}]}]
          }
        }
        """
    }

    static func helperIsExecutable(bundle: Bundle = .main) -> Bool {
        FileManager.default.isExecutableFile(
            atPath: helperURL(bundle: bundle).path
        )
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
    }
}

@MainActor
@Observable
final class SettingsModel {
    private(set) var settings: MoraeSettings
    private(set) var feeds: [FeedSource] = []
    private(set) var notificationState:
        AgentNotificationAuthorizationState = .unknown
    private(set) var hookStatuses: [
        AgentHookProvider: AgentHookInstallStatus
    ] = Dictionary(
        uniqueKeysWithValues: AgentHookProvider.allCases.map {
            ($0, .notInstalled)
        }
    )
    private(set) var installingHook: AgentHookProvider?
    private(set) var jiraSnapshot = JiraIntegrationSnapshot(
        connection: nil,
        lastAutomaticAttemptDay: nil,
        lastSuccessfulSyncAt: nil
    )
    private(set) var jiraStartDateFields: [JiraFieldDefinition] = []
    private(set) var jiraStatusMessage: String?
    private(set) var jiraStatusIsError = false
    private(set) var isJiraBusy = false
    private(set) var isBusy = false
    var errorMessage: String?

    private let store: any SettingsStoring
    private let agentRepository: (any AgentRepository)?
    private let feedRepository: (any FeedSourceRepository)?
    private let feedValidator: any FeedValidating
    private let notifier: (any AgentNotifying)?
    private let launchAtLogin: any LaunchAtLoginControlling
    private let clock: any Clock
    private let uuidGenerator: any UUIDGenerating
    private let jiraIntegration: JiraIntegrationService?
    private let hookInstaller: any AgentHookInstalling

    init(
        store: any SettingsStoring,
        agentRepository: (any AgentRepository)?,
        feedRepository: (any FeedSourceRepository)?,
        notifier: (any AgentNotifying)?,
        feedValidator: any FeedValidating = LiveFeedValidator(),
        launchAtLogin: any LaunchAtLoginControlling =
            SystemLaunchAtLoginController(),
        clock: any Clock,
        uuidGenerator: any UUIDGenerating,
        jiraIntegration: JiraIntegrationService? = nil,
        hookInstaller: any AgentHookInstalling =
            LiveAgentHookInstaller()
    ) {
        self.store = store
        self.agentRepository = agentRepository
        self.feedRepository = feedRepository
        self.notifier = notifier
        self.feedValidator = feedValidator
        self.launchAtLogin = launchAtLogin
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.jiraIntegration = jiraIntegration
        self.hookInstaller = hookInstaller
        var loaded = store.load()
        loaded.launchAtLogin = launchAtLogin.isEnabled()
        settings = loaded
    }

    func refresh() async {
        await refreshFeeds()
        await refreshNotifications()
        await refreshJira()
        refreshHooks()
    }

    func installHook(_ provider: AgentHookProvider) {
        guard installingHook == nil else { return }
        installingHook = provider
        errorMessage = nil
        defer { installingHook = nil }
        do {
            try hookInstaller.install(
                provider,
                sourceHelperURL: HookSnippetBuilder.helperURL()
            )
            refreshHooks()
        } catch {
            hookStatuses[provider] = .needsAttention(
                (error as? LocalizedError)?.errorDescription
                    ?? "자동 설정을 완료하지 못했습니다."
            )
        }
    }

    func installAllHooks() {
        guard installingHook == nil else { return }
        for provider in AgentHookProvider.allCases {
            installHook(provider)
        }
    }

    func connectJira(
        siteURL: String,
        email: String,
        token: String,
        startDateFieldID: String?
    ) async -> Bool {
        guard let jiraIntegration, !isJiraBusy else { return false }
        isJiraBusy = true
        jiraStatusMessage = nil
        jiraStatusIsError = false
        defer { isJiraBusy = false }
        do {
            let result = try await jiraIntegration.connect(
                siteURLText: siteURL,
                accountEmail: email,
                token: token,
                preferredStartDateFieldID: startDateFieldID
            )
            switch result {
            case let .connected(connection):
                jiraStartDateFields = []
                jiraStatusMessage =
                    "\(connection.displayBaseURL.host ?? "Jira") 연결을 완료했습니다."
                await refreshJira()
                return true
            case let .requiresStartDateFieldSelection(fields):
                jiraStartDateFields = fields
                jiraStatusMessage =
                    "가져오기에 사용할 시작 날짜 필드를 선택해 주세요."
                return false
            }
        } catch {
            jiraStatusIsError = true
            jiraStatusMessage = (error as? LocalizedError)?.errorDescription
                ?? "Jira 연결을 완료하지 못했습니다."
            return false
        }
    }

    func disconnectJira() async {
        guard let jiraIntegration, !isJiraBusy else { return }
        isJiraBusy = true
        jiraStatusMessage = nil
        jiraStatusIsError = false
        defer { isJiraBusy = false }
        do {
            try await jiraIntegration.disconnect()
            jiraStartDateFields = []
            jiraStatusMessage = "Jira 연결을 해제했습니다."
            await refreshJira()
        } catch {
            jiraStatusIsError = true
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Jira 연결을 해제하지 못했습니다."
        }
    }

    func syncJiraNow() async {
        guard let jiraIntegration, !isJiraBusy else { return }
        isJiraBusy = true
        jiraStatusMessage = nil
        jiraStatusIsError = false
        defer { isJiraBusy = false }
        do {
            let day = clock.localDay(
                for: clock.now(),
                calendar: .autoupdatingCurrent
            )
            let result = try await jiraIntegration.sync(
                day: day,
                mode: .manual
            )
            jiraStatusMessage = result.importedCount == 0
                ? "새 항목 없이 \(result.refreshedCount)개를 확인했습니다."
                : "\(result.importedCount)개를 추가하고 \(result.refreshedCount)개를 갱신했습니다."
            await refreshJira()
        } catch {
            jiraStatusIsError = true
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Jira 항목을 가져오지 못했습니다."
        }
    }

    func updateInterests(_ text: String) {
        settings.interests = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(20)
            .map(\.self)
        store.save(settings)
    }

    func setPrivacy(_ field: AgentPrivateField, enabled: Bool) async {
        errorMessage = nil
        if !enabled {
            do {
                try await agentRepository?.scrub([field])
            } catch {
                errorMessage = "기존 개인정보를 삭제하지 못해 설정을 유지했습니다."
                return
            }
        }
        switch field {
        case .projectPath: settings.storeProjectPath = enabled
        case .title: settings.storeAgentTitle = enabled
        case .lastMessage: settings.storeLastMessage = enabled
        }
        store.save(settings)
    }

    func setDetailedNotifications(_ enabled: Bool) {
        settings.showDetailsInNotification = enabled
        store.save(settings)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        errorMessage = nil
        do {
            try launchAtLogin.setEnabled(enabled)
            settings.launchAtLogin = launchAtLogin.isEnabled()
            store.save(settings)
        } catch {
            settings.launchAtLogin = launchAtLogin.isEnabled()
            errorMessage = "로그인 시 실행 설정을 변경하지 못했습니다."
        }
    }

    func requestNotifications() async {
        guard let notifier else { return }
        _ = await notifier.requestAuthorization()
        notificationState = await notifier.authorizationState()
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func addFeed(name: String, urlText: String) async -> Bool {
        errorMessage = nil
        let trimmedURL = urlText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let url = URL(string: trimmedURL),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            errorMessage = FeedManagementError.invalidHTTPSURL
                .localizedDescription
            return false
        }
        guard !feeds.contains(where: {
            $0.feedURL.absoluteString.caseInsensitiveCompare(
                url.absoluteString
            ) == .orderedSame
        }) else {
            errorMessage = FeedManagementError.duplicateURL.localizedDescription
            return false
        }
        let now = clock.now()
        let source = FeedSource(
            id: uuidGenerator.next(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? url.host!,
            feedURL: url,
            isOfficial: false,
            createdAt: now,
            updatedAt: now
        )
        isBusy = true
        defer { isBusy = false }
        do {
            try await feedValidator.validate(source)
            try await feedRepository?.add(source)
            await refreshFeeds()
            return true
        } catch let error as FeedSourceMappingError
            where error == .duplicateURL {
            errorMessage = FeedManagementError.duplicateURL.localizedDescription
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = FeedManagementError.unreadableFeed.localizedDescription
        }
        return false
    }

    func setFeedEnabled(_ source: FeedSource, enabled: Bool) async {
        do {
            try await feedRepository?.setEnabled(
                id: source.id,
                enabled: enabled,
                at: clock.now()
            )
            await refreshFeeds()
        } catch {
            errorMessage = "피드 상태를 변경하지 못했습니다."
        }
    }

    func deleteFeed(_ source: FeedSource) async {
        do {
            try await feedRepository?.deleteCustom(id: source.id)
            await refreshFeeds()
        } catch {
            errorMessage = "사용자 피드를 삭제하지 못했습니다."
        }
    }

    private func refreshFeeds() async {
        do {
            feeds = try await feedRepository?.allSources() ?? []
        } catch {
            errorMessage = "피드 목록을 불러오지 못했습니다."
        }
    }

    private func refreshNotifications() async {
        notificationState = await notifier?.authorizationState() ?? .unknown
    }

    private func refreshJira() async {
        guard let jiraIntegration else { return }
        jiraSnapshot = await jiraIntegration.snapshot()
    }

    private func refreshHooks() {
        for provider in AgentHookProvider.allCases {
            hookStatuses[provider] = hookInstaller.status(for: provider)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
