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

    init(
        clock: any Clock,
        menuBarContentLoader: any MenuBarContentLoading
    ) {
        self.clock = clock
        self.menuBarContentLoader = menuBarContentLoader
    }

    static func live() -> AppContainer {
        AppContainer(
            clock: SystemClock(),
            menuBarContentLoader: EmptyMenuBarContentLoader()
        )
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
