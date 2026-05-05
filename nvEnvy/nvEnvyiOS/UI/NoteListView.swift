import SwiftUI
import NvEnvyCore

struct NoteListView: View {
    @Environment(NotesViewModel.self) private var notesVM

    var body: some View {
        @Bindable var vm = notesVM
        List(selection: $vm.selectedNoteID) {
            ForEach(notesVM.sortedNotes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(note.modifiedDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(Optional(note.id))
            }
        }
        .navigationTitle("Notes")
        .searchable(text: $vm.searchQuery, placement: .navigationBarDrawer(displayMode: .always))
    }
}
