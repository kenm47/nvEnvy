import SwiftUI
import UIKit
import NvEnvyCore

struct NoteListView: View {
    @Environment(NotesViewModel.self) private var notesVM
    @Environment(IOSPreferences.self) private var prefs
    @FocusState private var searchFocused: Bool

    @State private var showingSettings = false
    @State private var showingBookmarks = false
    @State private var renamingNoteID: Note.ID?
    @State private var renameText = ""
    @State private var renameError: String?
    @State private var showingTagEditor = false
    @State private var tagEditingNoteID: Note.ID?
    @State private var pendingDeleteNoteID: Note.ID?

    // "Create <query>" row visibility is precomputed in the view model so this
    // body doesn't re-scan every title on each render.
    private var showCreateRow: Bool { notesVM.showCreateRow }

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
            if let tag = notesVM.tagFilter {
                HStack {
                    Text("Filtering by:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TagPill(tag: tag)
                    Spacer()
                    Button {
                        notesVM.tagFilter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(notesVM.sortedNotes) { note in
                noteRow(note)
                    .tag(Optional(note.id))
            }
            .onDelete { offsets in
                for index in offsets {
                    notesVM.deleteNote(noteID: notesVM.sortedNotes[index].id)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Notes")
        .searchable(text: $vm.searchQuery, placement: .navigationBarDrawer(displayMode: .always))
        .applySearchFocus($searchFocused)
        .onSubmit(of: .search) {
            notesVM.createOrSelectNote()
        }
        .refreshable {
            await notesVM.reconcileFilesystem()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ConflictBanner()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if notesVM.hasSnapback {
                    Button {
                        notesVM.snapback()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel("Go back to previous note")
                }
                sortMenu
                filterMenu
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(notesVM)
                .environment(prefs)
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksSheet().environment(notesVM)
        }
        .sheet(isPresented: $showingTagEditor) {
            if let id = tagEditingNoteID {
                TagEditorSheet(noteID: id).environment(notesVM)
            }
        }
        .alert("Rename Note", isPresented: renameAlertBinding, presenting: renamingNoteID) { noteID in
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { commitRename(noteID: noteID) }
        }
        .alert("Couldn't Rename", isPresented: Binding(
            get: { renameError != nil },
            set: { if !$0 { renameError = nil } }
        ), presenting: renameError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { pendingDeleteNoteID != nil },
                set: { if !$0 { pendingDeleteNoteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteNoteID { notesVM.deleteNote(noteID: id) }
                pendingDeleteNoteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteNoteID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyNextNote)) { _ in
            notesVM.selectNextNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyPreviousNote)) { _ in
            notesVM.selectPreviousNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyNewNote)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyDeleteSelectedNote)) { _ in
            if let id = notesVM.selectedNoteID { requestDelete(id) }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                SyncStatusIcon(status: note.syncStatus)
            }
            Text(note.cachedModifiedString)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        TagPill(tag: tag)
                    }
                    if note.tags.count > 3 {
                        Text("+\(note.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.title), modified \(note.cachedModifiedString)")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestDelete(note.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                beginRename(note)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                beginRename(note)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                tagEditingNoteID = note.id
                showingTagEditor = true
            } label: {
                Label("Edit Tags…", systemImage: "tag")
            }
            Button {
                UIPasteboard.general.string = note.body
            } label: {
                Label("Copy Note", systemImage: "doc.on.doc")
            }
            Button {
                UIPasteboard.general.string = NoteLinkBuilder.link(for: note)
            } label: {
                Label("Copy Note Link", systemImage: "link")
            }
            Divider()
            Button(role: .destructive) {
                requestDelete(note.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { prefs.sortField },
                set: { prefs.sortField = $0; notesVM.sortField = $0 }
            )) {
                ForEach(NotesViewModel.SortField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            Button {
                prefs.sortAscending.toggle()
                notesVM.sortAscending = prefs.sortAscending
            } label: {
                Label(prefs.sortAscending ? "Ascending" : "Descending",
                      systemImage: prefs.sortAscending ? "arrow.up" : "arrow.down")
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .accessibilityLabel("Sort")
    }

    private var filterMenu: some View {
        Menu {
            Section("Tags") {
                ForEach(notesVM.allKnownTags, id: \.self) { tag in
                    Button {
                        notesVM.tagFilter = (notesVM.tagFilter == tag) ? nil : tag
                    } label: {
                        if notesVM.tagFilter == tag {
                            Label(tag, systemImage: "checkmark")
                        } else {
                            Text(tag)
                        }
                    }
                }
            }
            Section("Bookmarks") {
                Button {
                    notesVM.saveBookmark()
                } label: {
                    Label("Save Search as Bookmark", systemImage: "bookmark")
                }
                .disabled(notesVM.searchQuery.isEmpty)

                ForEach(Array(notesVM.bookmarkStore.bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                    Button(bookmark.name) {
                        notesVM.restoreBookmark(index: index)
                    }
                }
                Button("Edit Bookmarks…") { showingBookmarks = true }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter and Bookmarks")
    }

    private func requestDelete(_ noteID: Note.ID) {
        if prefs.confirmDeletion {
            pendingDeleteNoteID = noteID
        } else {
            notesVM.deleteNote(noteID: noteID)
        }
    }

    private func beginRename(_ note: Note) {
        renameText = note.title
        renamingNoteID = note.id
    }

    private func commitRename(noteID: Note.ID) {
        if let error = notesVM.tryRenameNote(noteID: noteID, newTitle: renameText) {
            renameError = error
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingNoteID != nil },
            set: { if !$0 { renamingNoteID = nil } }
        )
    }
}

private extension View {
    /// `.searchFocused` is iOS 18+; the app targets iOS 17, so on 17 the ⌘L
    /// shortcut still posts `.nvEnvyFocusSearch` but can't drive focus
    /// programmatically — the notification observer just becomes a no-op.
    @ViewBuilder
    func applySearchFocus(_ binding: FocusState<Bool>.Binding) -> some View {
        if #available(iOS 18.0, *) {
            self.searchFocused(binding)
        } else {
            self
        }
    }
}
