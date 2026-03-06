import SwiftUI
import NvEnvyCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showTagEditor = false
    @State private var showDeleteConfirmation = false
    @State private var showNoEditorAlert = false
    @State private var noteToDelete: Note.ID?

    var body: some View {
        Group {
            if appState.notesFolderURL != nil {
                MainView()
            } else {
                FolderPickerPrompt()
            }
        }
        .sheet(isPresented: $showTagEditor) {
            if let id = appState.selectedNoteID {
                TagEditorPanel(noteID: id, isPresented: $showTagEditor)
                    .environment(appState)
            }
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let id = noteToDelete {
                    appState.deleteNote(noteID: id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let id = noteToDelete, let note = appState.note(for: id) {
                Text("Are you sure you want to delete \"\(note.title)\"? This cannot be undone.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyShowTagEditor)) { _ in
            if appState.selectedNoteID != nil {
                showTagEditor = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyConfirmDeleteNote)) { notification in
            if let id = notification.object as? Note.ID {
                noteToDelete = id
                showDeleteConfirmation = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyNoExternalEditor)) { _ in
            showNoEditorAlert = true
        }
        .alert("No External Editor", isPresented: $showNoEditorAlert) {
            Button("Open Preferences") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No external editor is configured. Set one in Preferences > General.")
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
