import SwiftUI
import NvEnvyCore

struct NoteListView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedNoteID: Note.ID?
    @State private var sortOrder: SortOrder = .modifiedDate

    enum SortOrder: String, CaseIterable {
        case title = "Title"
        case modifiedDate = "Date Modified"
        case createdDate = "Date Created"
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedNoteID) {
                ForEach(sortedNotes) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text("\(appState.filteredNotes.count) notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var sortedNotes: [Note] {
        switch sortOrder {
        case .title:
            return appState.filteredNotes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .modifiedDate:
            return appState.filteredNotes.sorted { $0.modifiedDate > $1.modifiedDate }
        case .createdDate:
            return appState.filteredNotes.sorted { $0.createdDate > $1.createdDate }
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.body)
                .lineLimit(1)
            Text(note.modifiedDate, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
