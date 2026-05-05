import SwiftUI
import NvEnvyCore

struct RootSplitView: View {
    @Environment(NotesViewModel.self) private var notesVM

    var body: some View {
        NavigationSplitView {
            NoteListView()
        } detail: {
            if let id = notesVM.selectedNoteID, let note = notesVM.note(for: id) {
                NoteEditorView(note: note, notesVM: notesVM)
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "doc.text")
            }
        }
    }
}
