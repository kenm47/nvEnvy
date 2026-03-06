import SwiftUI
import NvEnvyCore

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralPreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Notes Folder") {
                HStack {
                    if let url = appState.notesFolderURL {
                        Text(url.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.head)
                    } else {
                        Text("No folder selected")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change...") {
                        pickFolder()
                    }
                }
            }

            Section("Editor Font") {
                HStack {
                    Text(appState.editorFont.displayName ?? "System Font")
                    Text("\(Int(appState.editorFont.pointSize))pt")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change...") {
                        showFontPanel()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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

    private func showFontPanel() {
        NSFontManager.shared.orderFrontFontPanel(nil)
    }
}
