import SwiftUI
import UniformTypeIdentifiers
import NvEnvyCore

struct NoteListView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedNoteID: Note.ID?

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            if sortedNotes.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    if !appState.searchQuery.isEmpty {
                        Text("No results found")
                            .foregroundStyle(.secondary)
                        Button("Create \"\(appState.searchQuery)\"") {
                            appState.createOrSelectNote()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("No notes yet")
                            .foregroundStyle(.secondary)
                        Text("Type in the search field to create one.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedNoteID) {
                    ForEach(sortedNotes) { note in
                        if appState.noteListDisplayMode == .preview {
                            NotePreviewRow(note: note, appState: appState)
                                .tag(note.id)
                        } else {
                            NoteRow(note: note, appState: appState)
                                .tag(note.id)
                        }
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(appState.alternatingRowColors ? .enabled : .disabled)
                .onDrop(of: [.plainText, .rtf, .html, .fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                    return true
                }
                .contextMenu {
                    columnVisibilityMenu
                }
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

                sortMenu
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(AppState.SortField.allCases, id: \.self) { field in
                Button {
                    if appState.sortField == field {
                        appState.sortAscending.toggle()
                    } else {
                        appState.sortField = field
                        appState.sortAscending = false
                    }
                } label: {
                    HStack {
                        Text(field.displayName)
                        if appState.sortField == field {
                            Image(systemName: appState.sortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(appState.sortField.displayName)
                Image(systemName: appState.sortAscending ? "chevron.up" : "chevron.down")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Column Visibility Context Menu

    private var columnVisibilityMenu: some View {
        Group {
            Toggle("Tags", isOn: Binding(
                get: { appState.showTagsColumn },
                set: { appState.showTagsColumn = $0 }
            ))
            Toggle("Date Modified", isOn: Binding(
                get: { appState.showModifiedColumn },
                set: { appState.showModifiedColumn = $0 }
            ))
            Toggle("Date Created", isOn: Binding(
                get: { appState.showCreatedColumn },
                set: { appState.showCreatedColumn = $0 }
            ))
        }
    }

    // MARK: - Sorting (cached in AppState.sortedNotes)

    private var sortedNotes: [Note] { appState.sortedNotes }

    // MARK: - Drop

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
                Task { @MainActor in
                    let pasteboard = NSPasteboard.general
                    appState.importPasteboardItems(pasteboard.pasteboardItems ?? [])
                }
            }
        }
    }
}

// MARK: - Row Views

struct NoteRow: View {
    let note: Note
    let appState: AppState

    var body: some View {
        HStack {
            Text(note.title)
                .font(.system(size: appState.tableFontSize))
                .lineLimit(1)
            SyncStatusIcon(status: note.syncStatus)
            Spacer()
            Text(note.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.title), modified \(note.modifiedDate.formatted(date: .abbreviated, time: .shortened))")
    }
}

struct NotePreviewRow: View {
    let note: Note
    let appState: AppState

    private var firstLine: String {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.components(separatedBy: .newlines).first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(note.title)
                    .font(.system(size: appState.tableFontSize).bold())
                    .lineLimit(1)

                SyncStatusIcon(status: note.syncStatus)
            }

            if !firstLine.isEmpty {
                Text(firstLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if appState.showTagsColumn && !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags, id: \.self) { tag in
                        TagPill(tag: tag)
                            .onTapGesture { appState.tagFilter = tag }
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

struct SyncStatusIcon: View {
    let status: SyncStatus

    var body: some View {
        switch status {
        case .local, .current:
            EmptyView()
        case .uploading:
            Image(systemName: "cloud.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
                .accessibilityLabel("Uploading")
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .font(.caption2)
                .foregroundStyle(.blue)
                .accessibilityLabel("Downloading")
        case .conflict:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .accessibilityLabel("Sync conflict")
        }
    }
}
