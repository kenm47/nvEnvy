import SwiftUI

struct FirstLaunchView: View {
    let folderProvider: NotesFolderProvider
    let onPick: (URL) -> Void

    @State private var showingPicker = false

    private var hintedPath: String? {
        let value = NSUbiquitousKeyValueStore.default.string(forKey: "lastPickedNotesFolderPath")
        return (value?.isEmpty == false) ? value : nil
    }

    private var hintedFolderName: String? {
        guard let path = hintedPath else { return nil }
        return (path as NSString).lastPathComponent
    }

    private var startingDirectory: URL? {
        guard let path = hintedPath else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return nil }
        return URL(fileURLWithPath: parent)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            if let name = hintedFolderName {
                Text("Looks like you're using a notes folder named '\(name)' on your Mac.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Text("Tap below to open it.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose where to keep your notes")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text("Pick a folder. nvEnvy will read and write Markdown files there.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingPicker = true
            } label: {
                Text(hintedFolderName != nil ? "Open Folder" : "Choose Folder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .sheet(isPresented: $showingPicker) {
            FolderPicker(startingDirectory: startingDirectory) { url in
                folderProvider.saveBookmark(for: url)
                onPick(url)
                showingPicker = false
            }
            .ignoresSafeArea()
        }
        .onAppear {
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }
}
