import SwiftUI
import MoraeCore

@main
struct MoraeApp: App {
    var body: some Scene {
        MenuBarExtra("모래", systemImage: "circle.fill") {
            Text(MoraeRuntime.smokeMessage)
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
