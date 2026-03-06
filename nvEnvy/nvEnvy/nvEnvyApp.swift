import SwiftUI
import NvEnvyCore

@main
struct nvEnvyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}
