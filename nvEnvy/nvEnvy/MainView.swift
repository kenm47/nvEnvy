import SwiftUI
import NvEnvyCore

struct MainView: View {
    @Environment(AppState.self) private var appState

    private var windowTitle: String {
        if let id = appState.selectedNoteID, let note = appState.note(for: id) {
            return note.title
        }
        return "nvEnvy"
    }

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Snapback button
                if appState.hasSnapback {
                    Button {
                        appState.snapback()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go back to previous note")
                    .accessibilityHint("Return to the previous note in navigation history")
                }

                // Sync status indicator
                SyncStatusToolbarIndicator(appState: appState)

                SearchField(
                    query: $appState.searchQuery,
                    onReturn: {
                        if appState.isRenaming {
                            appState.commitRename()
                        } else {
                            appState.createOrSelectNote()
                        }
                    },
                    onEscape: {
                        if appState.isRenaming {
                            appState.isRenaming = false
                            appState.searchQuery = ""
                        } else {
                            appState.clearSearch()
                        }
                    }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if appState.noteListCollapsed {
                EditorView(selectedNoteID: appState.selectedNoteID)
                    .frame(minWidth: 300)
            } else if appState.layoutOrientation == .vertical {
                VSplitView {
                    NoteListView(selectedNoteID: $appState.selectedNoteID)
                        .frame(minHeight: 100, maxHeight: 300)
                    EditorView(selectedNoteID: appState.selectedNoteID)
                        .frame(minHeight: 200)
                }
            } else {
                HSplitView {
                    NoteListView(selectedNoteID: $appState.selectedNoteID)
                        .frame(minWidth: 180, maxWidth: 400)
                    EditorView(selectedNoteID: appState.selectedNoteID)
                        .frame(minWidth: 300)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(windowTitle)
        .background(
            KeyboardShortcutHandlers(appState: appState)
        )
        .background(WindowAccessor())
    }
}

// Sets frame autosave name on the NSWindow
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName("nvEnvyMainWindow")
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Invisible view for keyboard shortcuts
struct KeyboardShortcutHandlers: View {
    let appState: AppState

    var body: some View {
        Group {
            Button("") { appState.selectNextNote() }
                .keyboardShortcut("j", modifiers: .command)
            Button("") { appState.selectPreviousNote() }
                .keyboardShortcut("k", modifiers: .command)
            Button("") { appState.deselectNote() }
                .keyboardShortcut("d", modifiers: .command)
            Button("") {
                if let id = appState.selectedNoteID {
                    if appState.confirmDeletion {
                        NotificationCenter.default.post(name: .nvEnvyConfirmDeleteNote, object: id)
                    } else {
                        appState.deleteNote(noteID: id)
                    }
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            Button("") {
                if let id = appState.selectedNoteID {
                    appState.revealInFinder(noteID: id)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("") { appState.showWordCount.toggle() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("") { appState.showPreview.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .control])
            Button("") { appState.colorScheme = .blackWhite }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("") { appState.colorScheme = .lowContrast }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("") { appState.colorScheme = .custom }
                .keyboardShortcut("3", modifiers: [.command, .option])
            // ⌘⌥L — toggle layout
            Button("") {
                appState.layoutOrientation = appState.layoutOrientation == .horizontal ? .vertical : .horizontal
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            // ⌘⇧C — collapse/expand note list
            Button("") { appState.noteListCollapsed.toggle() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            // ⌘R — rename note
            Button("") { appState.startRename() }
                .keyboardShortcut("r", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

struct SyncStatusToolbarIndicator: View {
    let appState: AppState

    private var icon: String {
        let hasConflicts = appState.allNotes.contains { $0.syncStatus == .conflict }
        let hasSyncing = appState.allNotes.contains { $0.syncStatus == .uploading || $0.syncStatus == .downloading }
        if hasConflicts { return "exclamationmark.icloud" }
        if hasSyncing { return "arrow.triangle.2.circlepath" }
        return "checkmark.icloud"
    }

    private var color: Color {
        let hasConflicts = appState.allNotes.contains { $0.syncStatus == .conflict }
        if hasConflicts { return .orange }
        return .secondary
    }

    var body: some View {
        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
            .help(appState.syncHealthSummary)
            .accessibilityLabel("Sync status: \(appState.syncHealthSummary)")
    }
}

extension Notification.Name {
    static let nvEnvyConfirmDeleteNote = Notification.Name("nvEnvyConfirmDeleteNote")
}
