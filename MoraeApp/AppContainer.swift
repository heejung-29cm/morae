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
    let menuBarContentLoader: any MenuBarContentLoading
    let database: AppDatabase?
    let todoRepository: (any TodoRepository)?
    let startupError: AppError?

    init(
        clock: any Clock,
        menuBarContentLoader: any MenuBarContentLoading,
        database: AppDatabase? = nil,
        todoRepository: (any TodoRepository)? = nil,
        startupError: AppError? = nil
    ) {
        self.clock = clock
        self.menuBarContentLoader = menuBarContentLoader
        self.database = database
        self.todoRepository = todoRepository
        self.startupError = startupError
    }

    static func live() -> AppContainer {
        do {
            let paths = try AppDataDirectory().prepare()
            let database = try AppDatabase.open(at: paths.databaseURL)
            return AppContainer(
                clock: SystemClock(),
                menuBarContentLoader: EmptyMenuBarContentLoader(),
                database: database,
                todoRepository: GRDBTodoRepository(database: database)
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
