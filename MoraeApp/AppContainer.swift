import Foundation
import MoraeCore

struct MenuBarContent: Equatable, Sendable {
    let message: String
}

protocol MenuBarContentLoading: Sendable {
    func execute() async -> MenuBarContent
}

struct EmptyMenuBarContentLoader: MenuBarContentLoading {
    func execute() async -> MenuBarContent {
        MenuBarContent(message: MoraeRuntime.smokeMessage)
    }
}

@MainActor
final class AppContainer {
    let runtimeProfile: MoraeRuntimeProfile
    let clock: any Clock
    let uuidGenerator: any UUIDGenerating
    let menuBarContentLoader: any MenuBarContentLoading
    let settingsStore: any SettingsStoring
    let onboardingStore: any OnboardingStateStoring
    let database: AppDatabase?
    let todoRepository: (any TodoRepository)?
    let feedSourceRepository: (any FeedSourceRepository)?
    let articleRepository: (any ArticleRepository)?
    let briefingRepository: (any BriefingRepository)?
    let generateBriefing: (any BriefingGenerating)?
    let aiReportRepository: (any AIReportRepository)?
    let generateAIReport: (any AIReportGenerating)?
    let agentRepository: (any AgentRepository)?
    let receiveAgentEvent: ReceiveAgentEvent?
    let agentNotifier: (any AgentNotifying)?
    let agentActivity: AgentActivityModel?
    let agentSocketServer: AgentSocketServer?
    let jiraIntegration: JiraIntegrationService?
    let hookInstaller: any AgentHookInstalling
    let launchAtLoginController: any LaunchAtLoginControlling
    let startupError: AppError?

    init(
        runtimeProfile: MoraeRuntimeProfile = .standard,
        clock: any Clock,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator(),
        menuBarContentLoader: any MenuBarContentLoading,
        settingsStore: any SettingsStoring = UserDefaultsSettingsStore(),
        onboardingStore: any OnboardingStateStoring =
            UserDefaultsOnboardingStateStore(),
        database: AppDatabase? = nil,
        todoRepository: (any TodoRepository)? = nil,
        feedSourceRepository: (any FeedSourceRepository)? = nil,
        articleRepository: (any ArticleRepository)? = nil,
        briefingRepository: (any BriefingRepository)? = nil,
        generateBriefing: (any BriefingGenerating)? = nil,
        aiReportRepository: (any AIReportRepository)? = nil,
        generateAIReport: (any AIReportGenerating)? = nil,
        agentRepository: (any AgentRepository)? = nil,
        receiveAgentEvent: ReceiveAgentEvent? = nil,
        agentNotifier: (any AgentNotifying)? = nil,
        agentActivity: AgentActivityModel? = nil,
        agentSocketServer: AgentSocketServer? = nil,
        jiraIntegration: JiraIntegrationService? = nil,
        hookInstaller: any AgentHookInstalling =
            LiveAgentHookInstaller(),
        launchAtLoginController: any LaunchAtLoginControlling =
            SystemLaunchAtLoginController(),
        startupError: AppError? = nil
    ) {
        self.runtimeProfile = runtimeProfile
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.menuBarContentLoader = menuBarContentLoader
        self.settingsStore = settingsStore
        self.onboardingStore = onboardingStore
        self.database = database
        self.todoRepository = todoRepository
        self.feedSourceRepository = feedSourceRepository
        self.articleRepository = articleRepository
        self.briefingRepository = briefingRepository
        self.generateBriefing = generateBriefing
        self.aiReportRepository = aiReportRepository
        self.generateAIReport = generateAIReport
        self.agentRepository = agentRepository
        self.receiveAgentEvent = receiveAgentEvent
        self.agentNotifier = agentNotifier
        self.agentActivity = agentActivity
        self.agentSocketServer = agentSocketServer
        self.jiraIntegration = jiraIntegration
        self.hookInstaller = hookInstaller
        self.launchAtLoginController = launchAtLoginController
        self.startupError = startupError
    }

    static func live(
        profile: MoraeRuntimeProfile = .current()
    ) -> AppContainer {
        do {
            let paths: AppDataPaths
            if let sessionRootURL = profile.sessionRootURL {
                paths = try AppDataDirectory(
                    applicationSupportURL: {
                        sessionRootURL.appendingPathComponent(
                            "Application Support",
                            isDirectory: true
                        )
                    }
                ).prepare()
            } else {
                paths = try AppDataDirectory().prepare()
            }
            let database = try AppDatabase.open(at: paths.databaseURL)
            let clock = SystemClock()
            let uuidGenerator = SystemUUIDGenerator()
            let settingsStore = UserDefaultsSettingsStore(
                defaults: profile.makeUserDefaults(
                    resetPersistentDomain: profile.isFreshTest
                )
            )
            let onboardingStore = UserDefaultsOnboardingStateStore(
                defaults: profile.makeUserDefaults()
            )
            let todoRepository = GRDBTodoRepository(database: database)
            let feedSourceRepository = GRDBFeedSourceRepository(database: database)
            let articleRepository = GRDBArticleRepository(
                database: database,
                clock: clock
            )
            let briefingRepository = GRDBBriefingRepository(
                database: database,
                uuidGenerator: uuidGenerator
            )
            let aiReportRepository = DatabaseAIReportRepository(
                database: database,
                uuidGenerator: uuidGenerator
            )
            let now = clock.now()
            let defaultFeeds = try DefaultFeedLoader.load(at: now)
            try feedSourceRepository.seedDefaultsSynchronously(defaultFeeds)
            let agentRepository = GRDBAgentRepository(
                database: database,
                uuidGenerator: uuidGenerator
            )
            let agentNotifier: any AgentNotifying = profile.isFreshTest
                ? FreshTestAgentNotifier()
                : SystemAgentNotifier(privacy: settingsStore)
            let retention = AgentRetentionService(
                repository: agentRepository,
                clock: clock,
                defaults: profile.makeUserDefaults()
            )
            let receiveAgentEvent = ReceiveAgentEvent(
                repository: agentRepository,
                privacy: settingsStore,
                notifier: agentNotifier,
                retention: retention,
                uuidGenerator: uuidGenerator
            )
            let agentActivity = AgentActivityModel(
                repository: agentRepository
            )
            let jiraCredentialStore: any JiraCredentialStoring =
                profile.isFreshTest
                ? InMemoryJiraCredentialStore()
                : KeychainJiraCredentialStore()
            let jiraIntegration = JiraIntegrationService(
                connectionStore: UserDefaultsJiraConnectionStore(
                    defaults: profile.makeUserDefaults()
                ),
                credentialStore: jiraCredentialStore,
                client: LiveJiraClient(),
                todoRepository: todoRepository,
                clock: clock,
                uuidGenerator: uuidGenerator
            )
            if !profile.isFreshTest {
                Task {
                    await retention.pruneIfNeeded(force: true)
                }
            }
            let agentSocketServer = AgentSocketServer(
                endpointURL: AgentSocketEndpoint.defaultURL(),
                handler: ReceiveAgentEnvelopeHandler(
                    receiver: receiveAgentEvent
                )
            )
            let runningAgentSocketServer: AgentSocketServer?
            if profile.isFreshTest || ProcessInfo.processInfo.environment[
                "XCTestConfigurationFilePath"
            ] != nil {
                runningAgentSocketServer = nil
            } else {
                do {
                    try agentSocketServer.start()
                    runningAgentSocketServer = agentSocketServer
                } catch {
                    MoraeLogger(category: .agentIPC).error(
                        event: PublicLogToken("socket_start_failed")
                    )
                    runningAgentSocketServer = nil
                }
            }
            let hookInstaller: any AgentHookInstalling
            let launchAtLoginController: any LaunchAtLoginControlling
            if let sessionRootURL = profile.sessionRootURL {
                hookInstaller = LiveAgentHookInstaller(
                    homeDirectoryURL: sessionRootURL.appendingPathComponent(
                        "Home",
                        isDirectory: true
                    ),
                    applicationSupportURL: sessionRootURL
                        .appendingPathComponent(
                            "Application Support",
                            isDirectory: true
                        )
                )
                launchAtLoginController = InMemoryLaunchAtLoginController()
            } else {
                hookInstaller = LiveAgentHookInstaller()
                launchAtLoginController = SystemLaunchAtLoginController()
            }
            return AppContainer(
                runtimeProfile: profile,
                clock: clock,
                uuidGenerator: uuidGenerator,
                menuBarContentLoader: EmptyMenuBarContentLoader(),
                settingsStore: settingsStore,
                onboardingStore: onboardingStore,
                database: database,
                todoRepository: todoRepository,
                feedSourceRepository: feedSourceRepository,
                articleRepository: articleRepository,
                briefingRepository: briefingRepository,
                generateBriefing: GenerateBriefing(
                    todoRepository: todoRepository,
                    feedSourceRepository: feedSourceRepository,
                    feedClient: LiveFeedClient(),
                    articleRepository: articleRepository,
                    briefingRepository: briefingRepository,
                    preferences: settingsStore,
                    clock: clock,
                    uuidGenerator: uuidGenerator
                ),
                aiReportRepository: aiReportRepository,
                generateAIReport: GenerateAIReport(
                    repository: aiReportRepository,
                    scriptRunner: LiveAIReportScriptRunner(),
                    clock: clock
                ),
                agentRepository: agentRepository,
                receiveAgentEvent: receiveAgentEvent,
                agentNotifier: agentNotifier,
                agentActivity: agentActivity,
                agentSocketServer: runningAgentSocketServer,
                jiraIntegration: jiraIntegration,
                hookInstaller: hookInstaller,
                launchAtLoginController: launchAtLoginController
            )
        } catch {
            let startupError = AppError(
                code: "database_startup_failed",
                userMessage: "Morae could not open its local data.",
                recovery: "Check disk availability and folder permissions, then reopen Morae."
            )
            return AppContainer(
                runtimeProfile: profile,
                clock: SystemClock(),
                menuBarContentLoader: StaticMenuBarContentLoader(
                    message: [
                        startupError.userMessage,
                        startupError.recovery,
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                ),
                startupError: startupError
            )
        }
    }

    static func preview(
        message: String = "Preview"
    ) -> AppContainer {
        AppContainer(
            clock: SystemClock(),
            menuBarContentLoader: PreviewMenuBarContentLoader(message: message)
        )
    }
}

private struct PreviewMenuBarContentLoader: MenuBarContentLoading {
    let message: String

    func execute() async -> MenuBarContent {
        MenuBarContent(message: message)
    }
}

private struct StaticMenuBarContentLoader: MenuBarContentLoading {
    let message: String

    func execute() async -> MenuBarContent {
        MenuBarContent(message: message)
    }
}
