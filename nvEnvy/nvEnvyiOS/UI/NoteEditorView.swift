import SwiftUI
import NvEnvyCore

struct NoteEditorView: View {
    let note: Note
    let notesVM: NotesViewModel

    var body: some View {
        NoteUITextEditor(note: note, notesVM: notesVM)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        notesVM.deleteNote(noteID: note.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
    }
}
