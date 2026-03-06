import SwiftUI
import NvEnvyCore

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedNoteID: Note.ID?

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
                NoteListView(selectedNoteID: $selectedNoteID)
                    .frame(minWidth: 180, maxWidth: 400)

                EditorView(selectedNoteID: selectedNoteID)
                    .frame(minWidth: 300)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
