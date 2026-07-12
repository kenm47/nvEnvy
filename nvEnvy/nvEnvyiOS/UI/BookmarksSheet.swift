import SwiftUI
import NvEnvyCore

/// Touch port of macOS `BookmarkListView.swift` — rename/reorder/delete saved
/// searches. Restoring a bookmark is handled by the caller's menu (tapping a
/// row here only manages the list).
struct BookmarksSheet: View {
    @Environment(NotesViewModel.self) private var notesVM
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var editingName: String = ""

    var body: some View {
        @Bindable var vm = notesVM
        NavigationStack {
            Group {
                if vm.bookmarkStore.bookmarks.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
                                           description: Text("Save a search to create one."))
                } else {
                    List {
                        ForEach(Array(vm.bookmarkStore.bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                            HStack {
                                if editingID == bookmark.id {
                                    TextField("Name", text: $editingName, onCommit: {
                                        vm.bookmarkStore.rename(id: bookmark.id, to: editingName)
                                        editingID = nil
                                    })
                                } else {
                                    VStack(alignment: .leading) {
                                        Text(bookmark.name).font(.body)
                                        if !bookmark.searchQuery.isEmpty {
                                            Text("Search: \(bookmark.searchQuery)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if index < 9 {
                                        Text("⌘\(index + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button {
                                        editingName = bookmark.name
                                        editingID = bookmark.id
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                vm.bookmarkStore.remove(id: vm.bookmarkStore.bookmarks[index].id)
                            }
                        }
                        .onMove { from, to in
                            guard let sourceIndex = from.first else { return }
                            vm.bookmarkStore.reorder(from: sourceIndex, to: to)
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }
}
