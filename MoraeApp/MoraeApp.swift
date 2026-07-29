import SwiftUI

@main
struct MoraeApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        MenuBarExtra("모래", systemImage: "hourglass") {
            MenuBarRootView(container: container)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("설정은 이후 Sprint에서 제공됩니다.")
                .frame(width: 360, height: 180)
                .padding()
        }
    }
}
