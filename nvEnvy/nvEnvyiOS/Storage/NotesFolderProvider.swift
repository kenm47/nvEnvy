import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class NotesFolderProvider {
    static let bookmarkKey = "nvenvy.iOS.notesFolderBookmark"

    private(set) var resolvedURL: URL?

    func resolveSavedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale, let fresh = try? url.bookmarkData(options: .minimalBookmark) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        resolvedURL = url
        return url
    }

    func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: .minimalBookmark) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    var startingDirectory: URL?
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.directoryURL = startingDirectory
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            onPick(url)
        }
    }
}
