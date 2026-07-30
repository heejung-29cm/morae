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
            Text("설정은 이후 Sprint에서 제공됩니다.")
                .frame(width: 360, height: 180)
                .padding()
        }
    }
}
