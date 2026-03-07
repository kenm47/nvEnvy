import SwiftUI
import NvEnvyCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showTagEditor = false
    @State private var showDeleteConfirmation = false
    @State private var showNoEditorAlert = false
    @State private var showBookmarks = false
    @State private var noteToDelete: Note.ID?

    @State private var showConflictList = false

    var body: some View {
        Group {
            if appState.notesFolderURL != nil {
                VStack(spacing: 0) {
                    ConflictBanner()
                    MainView()
                }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $showTagEditor) {
            if let id = appState.selectedNoteID {
                TagEditorPanel(noteID: id, isPresented: $showTagEditor)
                    .environment(appState)
            }
        }
        .alert(String(localized: "Delete Note?"), isPresented: $showDeleteConfirmation) {
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
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyShowBookmarks)) { _ in
            showBookmarks = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyShowConflicts)) { _ in
            showConflictList = true
        }
        .sheet(isPresented: $showConflictList) {
            ConflictListView(isPresented: $showConflictList)
                .environment(appState)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkListView(isPresented: $showBookmarks)
                .environment(appState)
        }
        .alert(String(localized: "No External Editor"), isPresented: $showNoEditorAlert) {
            Button("Open Preferences") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No external editor is configured. Set one in Preferences > General.")
        }
    }
}

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var showQuickTips = false

    private var iCloudAvailable: Bool {
        FileManager.default.fileExists(atPath: NSString("~/Library/Mobile Documents/com~apple~CloudDocs").expandingTildeInPath)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text(String(localized: "Welcome to nvEnvy"))
                .font(.largeTitle)

            Text(String(localized: "A fast, keyboard-driven note-taking app."))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if iCloudAvailable {
                    Button {
                        createInICloud()
                    } label: {
                        Label("Create in iCloud Drive", systemImage: "icloud")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button {
                    createNewFolder()
                } label: {
                    Label(iCloudAvailable ? "Create in Documents" : "Create New Folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    chooseExistingFolder()
                } label: {
                    Label("Choose Existing Folder", systemImage: "folder")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    openObsidianVault()
                } label: {
                    Label("Open Obsidian Vault", systemImage: "link")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showQuickTips {
                QuickTipsOverlay(isPresented: $showQuickTips)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
    }

    private func createInICloud() {
        let iCloudPath = NSString("~/Library/Mobile Documents/com~apple~CloudDocs/nvEnvy Notes").expandingTildeInPath
        let url = URL(fileURLWithPath: iCloudPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        appState.setNotesFolder(url)
        showQuickTipsIfNeeded()
    }

    private func createNewFolder() {
        let docsPath = NSString("~/Documents/nvEnvy Notes").expandingTildeInPath
        let url = URL(fileURLWithPath: docsPath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        appState.setNotesFolder(url)
        showQuickTipsIfNeeded()
    }

    private func chooseExistingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder for your notes"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setNotesFolder(url)
        showQuickTipsIfNeeded()
    }

    private func openObsidianVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your Obsidian vault folder"
        panel.prompt = "Open"
        panel.directoryURL = URL(fileURLWithPath: NSString("~/Documents").expandingTildeInPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setNotesFolder(url)
        showQuickTipsIfNeeded()
    }

    private func showQuickTipsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasSeenQuickTips") else { return }
        UserDefaults.standard.set(true, forKey: "hasSeenQuickTips")
        withAnimation { showQuickTips = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            withAnimation { showQuickTips = false }
        }
    }
}

struct QuickTipsOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Tips")
                .font(.headline)
            Group {
                Label("**\u{2318}L** — Focus search field", systemImage: "magnifyingglass")
                Label("**Return** — Create or select a note", systemImage: "return")
                Label("**\u{2318}\u{21E7}T** — Edit tags", systemImage: "tag")
                Label("**Escape** — Return to search", systemImage: "escape")
            }
            .font(.callout)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .onTapGesture { withAnimation { isPresented = false } }
    }
}
