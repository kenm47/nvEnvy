import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Owns the lifetime of the app's security-scoped access grant to the notes
/// folder. `startAccessingSecurityScopedResource()` / `stopAccessing…()` calls
/// must balance — this type is the single place either is called from, so a
/// folder swap or relaunch can never leak or double-release the grant.
@MainActor
@Observable
final class NotesFolderProvider {
    static let bookmarkKey = "nvenvy.iOS.notesFolderBookmark"

    private(set) var resolvedURL: URL?
    private var isAccessing = false

    /// Resolves the persisted bookmark and begins access. Call once at launch.
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
        isAccessing = true
        resolvedURL = url
        return url
    }

    /// Adopts a URL freshly returned by `UIDocumentPickerViewController` — the
    /// picker's coordinator has already called `startAccessingSecurityScopedResource()`
    /// on it, so this only persists the bookmark and releases any *previous*
    /// folder's grant.
    func adoptPickedFolder(_ url: URL) {
        stopAccessing()
        saveBookmark(for: url)
        resolvedURL = url
        isAccessing = true
    }

    func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: .minimalBookmark) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    /// Releases the current access grant, if any. Do not call this on
    /// backgrounding — iOS preserves the grant while suspended, and this is
    /// only meant for folder swaps or teardown.
    func stopAccessing() {
        if isAccessing, let url = resolvedURL {
            url.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
        resolvedURL = nil
    }
}

/// `UIDocumentPickerViewController` renders as a blank sheet when it's
/// returned directly as `UIViewControllerRepresentable` content and nested
/// two SwiftUI sheets deep (e.g. Settings sheet → folder-picker sheet) — it
/// expects to be presented modally, not embedded as a child controller. The
/// fix is to hand back a plain host controller and have it `present()` the
/// picker itself.
struct FolderPicker: UIViewControllerRepresentable {
    var startingDirectory: URL?
    var onPick: (URL) -> Void
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard !context.coordinator.didPresent else { return }
        context.coordinator.didPresent = true

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.directoryURL = startingDirectory
        picker.delegate = context.coordinator
        DispatchQueue.main.async {
            uiViewController.present(picker, animated: true)
        }
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: (() -> Void)?
        var didPresent = false
        init(onPick: @escaping (URL) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
