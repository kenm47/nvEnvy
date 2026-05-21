import SwiftUI
import UniformTypeIdentifiers
import NvEnvyCore

struct NoteListView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedNoteID: Note.ID?

    private var trimmedQuery: String {
        appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasExactTitleMatch: Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        let lower = q.lowercased()
        return sortedNotes.contains { $0.title.lowercased() == lower }
    }

    private var showCreateRow: Bool {
        !trimmedQuery.isEmpty && !hasExactTitleMatch
    }

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
                    if showCreateRow {
                        Button {
                            appState.createOrSelectNote()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.tint)
                                Text("Create \"\(trimmedQuery)\"")
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(sortedNotes) { note in
                        Group {
                            if appState.noteListDisplayMode == .preview {
                                NotePreviewRow(note: note, appState: appState)
                            } else {
                                NoteRow(note: note, appState: appState)
                            }
                        }
                        .tag(note.id)
                        .contextMenu {
                            rowContextMenu(for: note)
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
                        if appState.sortField == field {
                            Image(systemName: appState.sortAscending ? "arrow.up" : "arrow.down")
                        }
                        Text(field.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.sortAscending ? "arrow.up" : "arrow.down")
                Text(appState.sortField.displayName)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Per-Row Context Menu

    @ViewBuilder
    private func rowContextMenu(for note: Note) -> some View {
        Button("Rename") {
            appState.inlineRenameNoteID = note.id
        }
        Button("Reveal in Finder") {
            appState.revealInFinder(noteID: note.id)
        }
        Divider()
        Button("Delete Note", role: .destructive) {
            if appState.confirmDeletion {
                NotificationCenter.default.post(name: .nvEnvyConfirmDeleteNote, object: note.id)
            } else {
                appState.deleteNote(noteID: note.id)
            }
        }
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
            InlineNoteTitle(note: note, appState: appState,
                            font: .system(size: appState.tableFontSize))
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
                InlineNoteTitle(note: note, appState: appState,
                                font: .system(size: appState.tableFontSize).bold())

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

// MARK: - Inline Rename Title

struct InlineNoteTitle: View {
    let note: Note
    let appState: AppState
    let font: Font

    @State private var draftTitle: String = ""
    @FocusState private var isFocused: Bool

    private var isEditing: Bool { appState.inlineRenameNoteID == note.id }

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .onKeyPress(.escape) {
                        cancel()
                        return .handled
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing { commit() }
                    }
            } else {
                Text(note.title)
                    .font(font)
                    .lineLimit(1)
            }
        }
        .onChange(of: isEditing, initial: true) { _, editing in
            if editing {
                draftTitle = note.title
                DispatchQueue.main.async { isFocused = true }
            }
        }
    }

    private func commit() {
        guard isEditing else { return }
        let result = appState.tryRenameNote(noteID: note.id, newTitle: draftTitle)
        if let error = result {
            appState.inlineRenameError = error
        }
        appState.inlineRenameNoteID = nil
    }

    private func cancel() {
        appState.inlineRenameNoteID = nil
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
