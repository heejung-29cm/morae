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
    let clock: any Clock
    let uuidGenerator: any UUIDGenerating
    let menuBarContentLoader: any MenuBarContentLoading
    let database: AppDatabase?
    let todoRepository: (any TodoRepository)?
    let feedSourceRepository: (any FeedSourceRepository)?
    let articleRepository: (any ArticleRepository)?
    let briefingRepository: (any BriefingRepository)?
    let generateBriefing: (any BriefingGenerating)?
    let agentRepository: (any AgentRepository)?
    let receiveAgentEvent: ReceiveAgentEvent?
    let agentNotifier: (any AgentNotifying)?
    let agentActivity: AgentActivityModel?
    let agentSocketServer: AgentSocketServer?
    let startupError: AppError?

    init(
        clock: any Clock,
        uuidGenerator: any UUIDGenerating = SystemUUIDGenerator(),
        menuBarContentLoader: any MenuBarContentLoading,
        database: AppDatabase? = nil,
        todoRepository: (any TodoRepository)? = nil,
        feedSourceRepository: (any FeedSourceRepository)? = nil,
        articleRepository: (any ArticleRepository)? = nil,
        briefingRepository: (any BriefingRepository)? = nil,
        generateBriefing: (any BriefingGenerating)? = nil,
        agentRepository: (any AgentRepository)? = nil,
        receiveAgentEvent: ReceiveAgentEvent? = nil,
        agentNotifier: (any AgentNotifying)? = nil,
        agentActivity: AgentActivityModel? = nil,
        agentSocketServer: AgentSocketServer? = nil,
        startupError: AppError? = nil
    ) {
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.menuBarContentLoader = menuBarContentLoader
        self.database = database
        self.todoRepository = todoRepository
        self.feedSourceRepository = feedSourceRepository
        self.articleRepository = articleRepository
        self.briefingRepository = briefingRepository
        self.generateBriefing = generateBriefing
        self.agentRepository = agentRepository
        self.receiveAgentEvent = receiveAgentEvent
        self.agentNotifier = agentNotifier
        self.agentActivity = agentActivity
        self.agentSocketServer = agentSocketServer
        self.startupError = startupError
    }

    static func live() -> AppContainer {
        do {
            let paths = try AppDataDirectory().prepare()
            let database = try AppDatabase.open(at: paths.databaseURL)
            let clock = SystemClock()
            let uuidGenerator = SystemUUIDGenerator()
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
            let now = clock.now()
            let defaultFeeds = try DefaultFeedLoader.load(at: now)
            try feedSourceRepository.seedDefaultsSynchronously(defaultFeeds)
            let agentRepository = GRDBAgentRepository(
                database: database,
                uuidGenerator: uuidGenerator
            )
            let agentNotifier = SystemAgentNotifier()
            let retention = AgentRetentionService(
                repository: agentRepository,
                clock: clock
            )
            let receiveAgentEvent = ReceiveAgentEvent(
                repository: agentRepository,
                privacy: UserDefaultsAgentPrivacyPolicyProvider(),
                notifier: agentNotifier,
                retention: retention,
                uuidGenerator: uuidGenerator
            )
            let agentActivity = AgentActivityModel(
                repository: agentRepository
            )
            Task {
                await retention.pruneIfNeeded(force: true)
            }
            let agentSocketServer = AgentSocketServer(
                endpointURL: AgentSocketEndpoint.defaultURL(),
                handler: ReceiveAgentEnvelopeHandler(
                    receiver: receiveAgentEvent
                )
            )
            let runningAgentSocketServer: AgentSocketServer?
            if ProcessInfo.processInfo.environment[
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
            return AppContainer(
                clock: clock,
                uuidGenerator: uuidGenerator,
                menuBarContentLoader: EmptyMenuBarContentLoader(),
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
                    preferences: UserDefaultsBriefingPreferences(),
                    clock: clock,
                    uuidGenerator: uuidGenerator
                ),
                agentRepository: agentRepository,
                receiveAgentEvent: receiveAgentEvent,
                agentNotifier: agentNotifier,
                agentActivity: agentActivity,
                agentSocketServer: runningAgentSocketServer
            )
        } catch {
            let startupError = AppError(
                code: "database_startup_failed",
                userMessage: "Morae could not open its local data.",
                recovery: "Check disk availability and folder permissions, then reopen Morae."
            )
            return AppContainer(
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
