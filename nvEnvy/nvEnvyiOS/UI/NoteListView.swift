import SwiftUI
import NvEnvyCore

struct NoteListView: View {
    @Environment(NotesViewModel.self) private var notesVM

    private var hasExactTitleMatch: Bool {
        let q = notesVM.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let lower = q.lowercased()
        return notesVM.sortedNotes.contains { $0.title.lowercased() == lower }
    }

    private var showCreateRow: Bool {
        let q = notesVM.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && !hasExactTitleMatch
    }

    var body: some View {
        @Bindable var vm = notesVM
        List(selection: $vm.selectedNoteID) {
            if showCreateRow {
                Button {
                    notesVM.createOrSelectNote()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                        Text("Create \"\(notesVM.searchQuery)\"")
                        Spacer()
                    }
                }
            }
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
            .onDelete { offsets in
                for index in offsets {
                    let note = notesVM.sortedNotes[index]
                    notesVM.deleteNote(noteID: note.id)
                }
            }
        }
        .navigationTitle("Notes")
        .searchable(text: $vm.searchQuery, placement: .navigationBarDrawer(displayMode: .always))
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyNextNote)) { _ in
            notesVM.selectNextNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyPreviousNote)) { _ in
            notesVM.selectPreviousNote()
        }
    }
}
