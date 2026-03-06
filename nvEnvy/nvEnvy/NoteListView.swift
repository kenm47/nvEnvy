import SwiftUI
import UniformTypeIdentifiers
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
                    if appState.noteListDisplayMode == .preview {
                        NotePreviewRow(note: note, onTagTap: { tag in
                            appState.tagFilter = tag
                        })
                        .tag(note.id)
                    } else {
                        NoteRow(note: note, onTagTap: { tag in
                            appState.tagFilter = tag
                        })
                        .tag(note.id)
                    }
                }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                return .ignored
            }
            .onDrop(of: [.plainText, .rtf, .html, .fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
                return true
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

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                            appState.importDirectory(url: url)
                        } else {
                            appState.importFiles(urls: [url])
                        }
                    }
                }
            } else {
                // Text/RTF/HTML pasteboard data
                Task { @MainActor in
                    let pasteboard = NSPasteboard.general
                    appState.importPasteboardItems(pasteboard.pasteboardItems ?? [])
                }
            }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.title), \(note.tags.isEmpty ? "" : "tags: \(note.tags.joined(separator: ", ")), ")modified \(note.modifiedDate.formatted(.relative(presentation: .named)))")
    }
}

struct NotePreviewRow: View {
    let note: Note
    var onTagTap: (String) -> Void

    private var firstLine: String {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.components(separatedBy: .newlines).first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.body.bold())
                .lineLimit(1)

            if !firstLine.isEmpty {
                Text(firstLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags, id: \.self) { tag in
                        TagPill(tag: tag)
                            .onTapGesture { onTagTap(tag) }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.title), \(note.tags.isEmpty ? "" : "tags: \(note.tags.joined(separator: ", ")), ")modified \(note.modifiedDate.formatted(.relative(presentation: .named)))")
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
            .accessibilityLabel(tag)
            .accessibilityHint("Filter by this tag")
            .accessibilityAddTraits(.isButton)
    }

    private var tagColor: Color {
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .indigo]
        return colors[hash % colors.count]
    }
}
