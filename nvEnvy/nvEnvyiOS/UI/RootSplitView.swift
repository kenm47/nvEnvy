import SwiftUI
import NvEnvyCore

struct RootSplitView: View {
    @Environment(NotesViewModel.self) private var notesVM

    var body: some View {
        NavigationSplitView {
            NoteListView()
        } detail: {
            if let id = notesVM.selectedNoteID, let note = notesVM.note(for: id) {
                NoteReaderView(note: note)
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "doc.text")
            }
        }
    }
}
