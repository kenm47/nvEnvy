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
                        if !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            appState.createOrSelectNote()
                        }
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .nvEnvyFocusEditor, object: nil)
                        }
                    },
                    onEscape: {
                        appState.clearSearch()
                    },
                    onDownArrow: {
                        appState.selectNextNote()
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
        .background(BacktabMonitor())
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

// Monitors Shift+Tab on the note list (NSTableView) to move focus to search
struct BacktabMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = BacktabView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    class BacktabView: NSView {
        var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard let fr = self.window?.firstResponder else { return event }
                let isTableFocused = fr is NSTableView ||
                    (fr is NSView && (fr as? NSView)?.enclosingScrollView?.documentView is NSTableView)
                guard isTableFocused else { return event }

                // Shift+Tab from note list → search field
                if event.keyCode == 48, event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .nvEnvyFocusSearchField, object: nil)
                    return nil
                }
                // Tab or Enter from note list → editor
                if event.keyCode == 48 || event.keyCode == 36 {
                    NotificationCenter.default.post(name: .nvEnvyFocusEditor, object: nil)
                    return nil
                }
                return event
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
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
            // ⌘R — inline rename selected note
            Button("") {
                if let id = appState.selectedNoteID {
                    appState.inlineRenameNoteID = id
                }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

struct SyncStatusToolbarIndicator: View {
    let appState: AppState

    private enum SyncState {
        case conflict, syncing, synced

        var icon: String {
            switch self {
            case .conflict: "exclamationmark.icloud"
            case .syncing: "arrow.triangle.2.circlepath"
            case .synced: "checkmark.icloud"
            }
        }

        var color: Color {
            switch self {
            case .conflict: .orange
            case .syncing, .synced: .secondary
            }
        }
    }

    private var syncState: SyncState {
        var hasConflict = false
        var hasSyncing = false
        for note in appState.allNotes {
            switch note.syncStatus {
            case .conflict: hasConflict = true
            case .uploading, .downloading: hasSyncing = true
            default: break
            }
            if hasConflict { break }
        }
        if hasConflict { return .conflict }
        if hasSyncing { return .syncing }
        return .synced
    }

    var body: some View {
        Image(systemName: syncState.icon)
            .font(.caption)
            .foregroundStyle(syncState.color)
            .help(appState.syncHealthSummary)
            .accessibilityLabel("Sync status: \(appState.syncHealthSummary)")
    }
}

extension Notification.Name {
    static let nvEnvyConfirmDeleteNote = Notification.Name("nvEnvyConfirmDeleteNote")
}
