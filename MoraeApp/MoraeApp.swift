import SwiftUI

@main
struct MoraeApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(container: container)
        } label: {
            Label(
                "모래",
                systemImage: container.agentActivity?.hasUnread == true
                    ? "hourglass.bottomhalf.filled"
                    : "hourglass"
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(container: container)
        }
    }
}
