import SwiftUI
import NvEnvyCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.notesFolderURL != nil {
                MainView()
            } else {
                FolderPickerPrompt()
            }
        }
    }
}

struct FolderPickerPrompt: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to nvEnvy")
                .font(.largeTitle)
            Text("Choose a folder to store your notes.")
                .foregroundStyle(.secondary)
            Button("Choose Notes Folder...") {
                pickFolder()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder for your notes"
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setNotesFolder(url)
    }
}
