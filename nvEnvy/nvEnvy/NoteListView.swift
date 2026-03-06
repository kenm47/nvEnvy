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
                    NoteRow(note: note, onTagTap: { tag in
                        appState.tagFilter = tag
                    })
                    .tag(note.id)
                }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                // Return in list -> could focus editor, but SwiftUI doesn't give us direct focus control
                return .ignored
            }

            Divider()

            HStack {
                if let tag = appState.tagFilter {
                    HStack(spacing: 4) {
                        Text("Tag: \(tag)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            appState.tagFilter = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("\(appState.filteredNotes.count) notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    var onTagTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.body)
                .lineLimit(1)

            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags, id: \.self) { tag in
                        TagPill(tag: tag)
                            .onTapGesture { onTagTap(tag) }
                    }
                }
            }

            Text(note.modifiedDate, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor.opacity(0.2), in: Capsule())
            .foregroundStyle(tagColor)
    }

    private var tagColor: Color {
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .indigo]
        return colors[hash % colors.count]
    }
}
