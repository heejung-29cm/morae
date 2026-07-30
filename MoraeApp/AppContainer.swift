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
    let generateBriefing: GenerateBriefing?
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
        generateBriefing: GenerateBriefing? = nil,
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
                )
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
