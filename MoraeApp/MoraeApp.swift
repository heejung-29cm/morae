import SwiftUI

@main
struct MoraeApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        MenuBarExtra("모래", systemImage: "circle.fill") {
            MenuBarRootView(loader: container.menuBarContentLoader)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private struct MenuBarRootView: View {
    let loader: any MenuBarContentLoading
    @State private var content = MenuBarContent(message: "")

    var body: some View {
        Text(content.message)
            .padding()
            .task {
                content = await loader.execute()
            }
    }
}
