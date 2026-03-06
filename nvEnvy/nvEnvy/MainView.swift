import SwiftUI
import NvEnvyCore

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            SearchField(
                query: $appState.searchQuery,
                onReturn: { appState.createOrSelectNote() },
                onEscape: { appState.clearSearch() }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            HSplitView {
                NoteListView(selectedNoteID: $appState.selectedNoteID)
                    .frame(minWidth: 180, maxWidth: 400)

                EditorView(selectedNoteID: appState.selectedNoteID)
                    .frame(minWidth: 300)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(
            KeyboardShortcutHandlers(appState: appState)
        )
    }
}

// Invisible view for keyboard shortcuts
struct KeyboardShortcutHandlers: View {
    let appState: AppState

    var body: some View {
        Group {
            // ⌘J — next note
            Button("") { appState.selectNextNote() }
                .keyboardShortcut("j", modifiers: .command)
            // ⌘K — previous note
            Button("") { appState.selectPreviousNote() }
                .keyboardShortcut("k", modifiers: .command)
            // ⌘D — deselect
            Button("") { appState.deselectNote() }
                .keyboardShortcut("d", modifiers: .command)
            // ⌘Delete — delete note
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
            // ⌘⇧R — reveal in Finder
            Button("") {
                if let id = appState.selectedNoteID {
                    appState.revealInFinder(noteID: id)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            // ⇧⌘K — toggle word count
            Button("") { appState.showWordCount.toggle() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            // ⌃⌘P — toggle preview
            Button("") { appState.showPreview.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .control])
            // ⌘⌥1 — B/W scheme
            Button("") { appState.colorScheme = .blackWhite }
                .keyboardShortcut("1", modifiers: [.command, .option])
            // ⌘⌥2 — Low Contrast
            Button("") { appState.colorScheme = .lowContrast }
                .keyboardShortcut("2", modifiers: [.command, .option])
            // ⌘⌥3 — Custom
            Button("") { appState.colorScheme = .custom }
                .keyboardShortcut("3", modifiers: [.command, .option])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

extension Notification.Name {
    static let nvEnvyConfirmDeleteNote = Notification.Name("nvEnvyConfirmDeleteNote")
}
