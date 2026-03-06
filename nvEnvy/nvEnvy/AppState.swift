import Foundation
import AppKit
import NvEnvyCore

private let kNotesFolderBookmarkKey = "notesFolderBookmark"
private let kEditorFontNameKey = "editorFontName"
private let kEditorFontSizeKey = "editorFontSize"

@MainActor
@Observable
public final class AppState {
    public var searchQuery: String = "" {
        didSet { performSearch() }
    }
    public var allNotes: [Note] = []
    public var filteredNotes: [Note] = []
    public private(set) var notesFolderURL: URL?
    public var editorFont: NSFont

    private var noteStore: NoteStore?
    private var storageService: FileStorageService?
    private var searchEngine = SearchEngine()
    private var fileMonitor: FileSystemMonitor?

    public init() {
        let savedName = UserDefaults.standard.string(forKey: kEditorFontNameKey)
        let savedSize = UserDefaults.standard.double(forKey: kEditorFontSizeKey)
        if let name = savedName, savedSize > 0,
           let font = NSFont(name: name, size: savedSize) {
            self.editorFont = font
        } else {
            self.editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        }
        restoreNotesFolder()
    }

    // MARK: - Folder Management

    public func setNotesFolder(_ url: URL) {
        // Save security-scoped bookmark
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: kNotesFolderBookmarkKey)
        } catch {
            // Fall through — we'll still use the URL for this session
        }

        notesFolderURL = url
        setupStorage(url: url)
    }

    private func restoreNotesFolder() {
        guard let data = UserDefaults.standard.data(forKey: kNotesFolderBookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if isStale {
            // Re-save bookmark
            if let newData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(newData, forKey: kNotesFolderBookmarkKey)
            }
        }

        guard url.startAccessingSecurityScopedResource() else { return }
        notesFolderURL = url
        setupStorage(url: url)
    }

    private func setupStorage(url: URL) {
        let storage = FileStorageService(notesDirectory: url)
        self.storageService = storage
        let store = NoteStore(storage: storage)
        self.noteStore = store

        // Start file monitoring
        fileMonitor?.stop()
        fileMonitor = FileSystemMonitor(directory: url) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reconcileFilesystem()
            }
        }
        fileMonitor?.start()

        // Load notes
        Task {
            try? await store.loadAll()
            self.allNotes = await store.allNotes()
            self.filteredNotes = self.allNotes
        }
    }

    // MARK: - Search

    private func performSearch() {
        filteredNotes = searchEngine.filter(notes: allNotes, query: searchQuery)
    }

    public func clearSearch() {
        searchQuery = ""
    }

    public func createOrSelectNote() {
        guard !searchQuery.isEmpty else { return }

        // Check for exact match
        if let match = searchEngine.exactTitleMatch(notes: allNotes, query: searchQuery) {
            // Just select it — the UI binding will handle focus
            filteredNotes = [match]
            return
        }

        // Create new note
        let title = searchQuery
        Task {
            guard let store = noteStore else { return }
            let note = try await store.createNote(title: title)
            allNotes.append(note)
            filteredNotes = [note]
            searchQuery = ""
        }
    }

    // MARK: - Note Operations

    public func note(for id: UUID) -> Note? {
        allNotes.first { $0.id == id }
    }

    public func updateNoteBody(noteID: UUID, body: String) {
        guard let note = note(for: noteID) else { return }
        note.body = body
        note.modifiedDate = Date()
        note.invalidateSearchCache()

        Task {
            await noteStore?.updateBody(noteID: noteID, body: body)
        }
    }

    public func deleteNote(noteID: UUID) {
        Task {
            try? await noteStore?.deleteNote(noteID: noteID)
            allNotes.removeAll { $0.id == noteID }
            performSearch()
        }
    }

    // MARK: - File System Reconciliation

    private func reconcileFilesystem() async {
        guard let store = noteStore else { return }
        try? await store.reconcileWithFilesystem()
        allNotes = await store.allNotes()
        performSearch()
    }

    // MARK: - Font

    public func setEditorFont(_ font: NSFont) {
        editorFont = font
        UserDefaults.standard.set(font.fontName, forKey: kEditorFontNameKey)
        UserDefaults.standard.set(Double(font.pointSize), forKey: kEditorFontSizeKey)
    }

    // MARK: - Flush on quit

    public func flushBeforeQuit() async {
        await noteStore?.flushDirtyNotes()
    }
}
