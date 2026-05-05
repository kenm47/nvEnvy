import SwiftUI
import NvEnvyCore

@main
struct nvEnvyiOSApp: App {
    @State private var notesVM = NotesViewModel()
    @State private var folderProvider = NotesFolderProvider()
    @State private var folderResolved = false

    var body: some Scene {
        WindowGroup {
            Group {
                if folderResolved, notesVM.notesFolderURL != nil {
                    RootSplitView()
                        .environment(notesVM)
                } else {
                    FirstLaunchView(folderProvider: folderProvider) { url in
                        attach(url: url)
                    }
                }
            }
            .onAppear {
                if let url = folderProvider.resolveSavedBookmark() {
                    attach(url: url)
                }
            }
            .onOpenURL { url in
                notesVM.handleURL(url)
            }
        }
    }

    private func attach(url: URL) {
        notesVM.attach(folderURL: url)
        folderResolved = true
    }
}
