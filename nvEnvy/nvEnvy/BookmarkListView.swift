import SwiftUI
import NvEnvyCore

struct BookmarkListView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var editingID: UUID?
    @State private var editingName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Text("Bookmarks")
                .font(.headline)
                .padding(.top, 12)

            if appState.bookmarkStore.bookmarks.isEmpty {
                Text("No bookmarks saved.\nPress \u{2318}S to save a bookmark.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(appState.bookmarkStore.bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                        HStack {
                            if editingID == bookmark.id {
                                TextField("Name", text: $editingName, onCommit: {
                                    appState.bookmarkStore.rename(id: bookmark.id, to: editingName)
                                    editingID = nil
                                })
                                .textFieldStyle(.roundedBorder)
                            } else {
                                VStack(alignment: .leading) {
                                    Text(bookmark.name)
                                        .font(.body)
                                    if !bookmark.searchQuery.isEmpty {
                                        Text("Search: \(bookmark.searchQuery)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    appState.restoreBookmark(index: index)
                                    isPresented = false
                                }

                                Spacer()

                                if index < 9 {
                                    Text("\u{2318}\(index + 1)")
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

                                Button {
                                    appState.bookmarkStore.remove(id: bookmark.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onMove { from, to in
                        guard let sourceIndex = from.first else { return }
                        appState.bookmarkStore.reorder(from: sourceIndex, to: to)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .frame(width: 400, height: 350)
    }
}
