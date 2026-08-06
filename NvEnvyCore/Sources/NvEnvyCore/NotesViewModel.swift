import Foundation

/// Platform-agnostic notes view model. Owns the notes data, search, sort,
/// selection, snapback nav, bookmarks, sync health, and CRUD operations.
///
/// On macOS, `AppState` wraps an instance and forwards its public surface so
/// existing UI files don't change. iOS uses this directly.
///
/// Hooks (`onTagsChanged`, `onURLActivation`, `onNoteCommitted`) let the platform shell layer
/// react to changes the VM doesn't know about — e.g. Finder tag mirroring on
/// macOS, or `NSApp.activate` after a URL scheme handoff.
@MainActor
@Observable
public final class NotesViewModel {
    // MARK: - Notes Data

    public var allNotes: [Note] = [] {
        didSet {
            _cachedKnownTags = nil
            rebuildNotesByID()
        }
    }
    public var filteredNotes: [Note] = [] {
        didSet { rebuildSortedNotes() }
    }
    public var sortedNotes: [Note] = []

    /// Whether the list should show a "Create <query>" row: true when the
    /// trimmed search query is non-empty and no existing note has that exact
    /// title. Precomputed in `rebuildSortedNotes()` so the view body doesn't
    /// re-scan every title (with per-title lowercasing) on each render.
    public private(set) var showCreateRow: Bool = false

    public var selectedNoteID: Note.ID?

    private var notesByID: [UUID: Note] = [:]
    private var notesByFilename: [String: Note] = [:]
    private var _cachedKnownTags: [String]?

    public var allKnownTags: [String] {
        if let cached = _cachedKnownTags { return cached }
        let tags = Array(Set(allNotes.flatMap(\.tags))).sorted()
        _cachedKnownTags = tags
        return tags
    }

    // MARK: - Storage

    public private(set) var notesFolderURL: URL?
    public var allowedExtensions: [String] = ["md", "markdown", "mmd", "txt", "text"]

    private var noteStore: NoteStore?
    private var storageService: FileStorageService?
    private let searchActor = SearchActor()

    // MARK: - Search

    private var searchDebounceTask: Task<Void, Never>?

    public var searchQuery: String = "" {
        didSet {
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                await self.performSearch()
            }
        }
    }

    public var tagFilter: String? {
        didSet {
            Task { @MainActor [weak self] in await self?.performSearch() }
        }
    }

    // MARK: - Sort

    public enum SortField: Int, CaseIterable, Sendable {
        case title = 0
        case modifiedDate = 1
        case createdDate = 2
        case tags = 3

        public var displayName: String {
            switch self {
            case .title: return "Title"
            case .modifiedDate: return "Date Modified"
            case .createdDate: return "Date Created"
            case .tags: return "Tags"
            }
        }
    }

    public var sortField: SortField = .modifiedDate {
        didSet { rebuildSortedNotes() }
    }
    public var sortAscending: Bool = false {
        didSet { rebuildSortedNotes() }
    }

    // MARK: - Snapback / Wikilink Navigation

    public var snapbackStack: [Note.ID] = []
    public var hasSnapback: Bool { !snapbackStack.isEmpty }

    // MARK: - Bookmarks

    public var bookmarkStore = BookmarkStore()

    // MARK: - Preview / Rename UI state

    public var showPreview: Bool = false
    public var previewStickyNoteID: Note.ID?
    public var isRenaming: Bool = false

    // MARK: - Hooks

    /// Invoked after a note's tags change. macOS uses this to mirror tags into
    /// Finder tags when the user pref is enabled. iOS leaves it nil.
    public var onTagsChanged: ((Note) -> Void)?

    /// Invoked after `handleURL` processed a URL — typically used to bring the
    /// app to the foreground (`NSApp.activate` on macOS).
    public var onURLActivation: (() -> Void)?

    /// Invoked once `createOrSelectNote()` has committed a selection — either an
    /// existing note matched by title, or a newly created one. macOS uses this to
    /// move focus into the editor. Creation is asynchronous, so this is the only
    /// point at which the note is guaranteed to exist and be selected; callers
    /// must not assume the selection has landed when `createOrSelectNote()`
    /// returns. iOS leaves it nil.
    public var onNoteCommitted: ((Note.ID) -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Storage Lifecycle

    /// Wire up storage, NoteStore, and trigger initial load. Call after the
    /// notes folder URL is known.
    public func attach(
        folderURL: URL,
        allowedExtensions: Set<String>? = nil,
        coordinator: FileAccessCoordinator = PassthroughFileAccessCoordinator(),
        onInitialLoad: (() -> Void)? = nil
    ) {
        if let exts = allowedExtensions {
            self.allowedExtensions = Array(exts).sorted()
        }
        notesFolderURL = folderURL
        let storage = FileStorageService(
            notesDirectory: folderURL,
            allowedExtensions: Set(self.allowedExtensions),
            coordinator: coordinator
        )
        self.storageService = storage
        let store = NoteStore(storage: storage)
        self.noteStore = store

        Task {
            try? await store.loadAll()
            self.allNotes = await store.allNotes()
            self.filteredNotes = self.allNotes
            onInitialLoad?()
        }
    }

    // MARK: - Search

    /// Runs the (heavy) filter on `searchActor` off the main actor, then
    /// applies the results back on the main actor. The result is dropped if a
    /// newer query has superseded this one while filtering was in flight, so a
    /// slow search can't overwrite the list with stale results.
    private func performSearch() async {
        let query = searchQuery
        let snapshot = allNotes
        let results = await searchActor.filter(notes: snapshot, query: query)
        guard query == searchQuery else { return }
        if let tag = tagFilter {
            filteredNotes = results.filter { $0.tags.contains(tag) }
        } else {
            filteredNotes = results
        }
    }

    public func clearSearch() {
        searchQuery = ""
        tagFilter = nil
        // The `searchQuery` didSet just scheduled a debounced search; cancel it
        // and run the (empty-query) search immediately so the list clears now.
        searchDebounceTask?.cancel()
        Task { @MainActor [weak self] in await self?.performSearch() }
    }

    public func createOrSelectNote() {
        let title = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if let match = SearchEngine.exactTitleMatch(notes: allNotes, query: title) {
            filteredNotes = [match]
            selectedNoteID = match.id
            onNoteCommitted?(match.id)
            return
        }

        Task {
            guard let store = noteStore else { return }
            let note = try await store.createNote(title: title)
            allNotes.append(note)
            filteredNotes = [note]
            selectedNoteID = note.id
            searchQuery = ""
            onNoteCommitted?(note.id)
        }
    }

    // MARK: - Sorting

    private func rebuildNotesByID() {
        notesByID = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })
        notesByFilename = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.filename, $0) })
    }

    private func rebuildSortedNotes() {
        updateShowCreateRow()
        // When a search is active, preserve the relevance ordering from SearchEngine
        if !searchQuery.isEmpty {
            sortedNotes = filteredNotes
            return
        }
        let notes = filteredNotes
        let ascending = sortAscending
        switch sortField {
        case .title:
            sortedNotes = notes.sorted {
                let cmp = $0.title.localizedCaseInsensitiveCompare($1.title)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .modifiedDate:
            sortedNotes = notes.sorted { ascending ? $0.modifiedDate < $1.modifiedDate : $0.modifiedDate > $1.modifiedDate }
        case .createdDate:
            sortedNotes = notes.sorted { ascending ? $0.createdDate < $1.createdDate : $0.createdDate > $1.createdDate }
        case .tags:
            sortedNotes = notes.sorted {
                let t0 = $0.tags.first ?? ""
                let t1 = $1.tags.first ?? ""
                let cmp = t0.localizedCaseInsensitiveCompare(t1)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
    }

    private func updateShowCreateRow() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showCreateRow = false
            return
        }
        showCreateRow = SearchEngine.exactTitleMatch(notes: filteredNotes, query: trimmed) == nil
    }

    public func note(for id: UUID) -> Note? {
        notesByID[id]
    }

    // MARK: - CRUD

    private var bodyUpdateTask: Task<Void, Never>?
    /// The most recent body edit that hasn't yet been flushed to `NoteStore`
    /// (and therefore hasn't been WAL-recorded). `flushBeforeQuit` must apply
    /// this synchronously instead of just cancelling the debounce task, or the
    /// last <500ms of typing is silently lost on background/quit.
    private var pendingBodyUpdate: (noteID: UUID, body: String)?

    public func updateNoteBody(noteID: UUID, body: String) {
        guard let note = note(for: noteID) else { return }
        note.body = body
        note.modifiedDate = Date()
        pendingBodyUpdate = (noteID, body)

        // Debounce expensive work: search cache invalidation, WAL write.
        bodyUpdateTask?.cancel()
        bodyUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.pendingBodyUpdate = nil
            note.invalidateSearchCache()
            await self.noteStore?.updateBody(noteID: noteID, body: body)
        }
    }

    public func updateNoteTags(noteID: UUID, tags: [String]) {
        guard let note = note(for: noteID) else { return }
        note.tags = tags
        note.modifiedDate = Date()
        note.invalidateSearchCache()
        _cachedKnownTags = nil

        Task {
            await noteStore?.updateTags(noteID: noteID, tags: tags)
        }

        onTagsChanged?(note)
    }

    public func deleteNote(noteID: UUID) {
        // Optimistic UI: remove from memory + clear selection synchronously
        // so the row disappears immediately. The on-disk delete (which may be
        // slow under iCloud sync) runs in the background.
        allNotes.removeAll { $0.id == noteID }
        if selectedNoteID == noteID {
            selectedNoteID = nil
        }
        // Drop the row from the visible list immediately, then reconcile the
        // full filtered/sorted set off the main actor.
        filteredNotes.removeAll { $0.id == noteID }
        Task { @MainActor [weak self] in await self?.performSearch() }
        Task {
            try? await noteStore?.deleteNote(noteID: noteID)
        }
    }

    public func renameNote(noteID: UUID, newTitle: String) {
        Task {
            try? await noteStore?.updateTitle(noteID: noteID, title: newTitle)
            if let note = note(for: noteID) {
                note.title = newTitle
                note.invalidateSearchCache()
            }
            // `filename` may have changed as part of the store's rename (it
            // mutates the shared `Note` in place, so `allNotes`'s didSet never
            // fires) — refresh the filename index so it doesn't point at a
            // stale key.
            rebuildNotesByID()
            await performSearch()
        }
    }

    /// Validating rename. Returns `nil` on success, or a user-facing error
    /// string on validation failure (empty title or filename collision with
    /// another existing note).
    public func tryRenameNote(noteID: UUID, newTitle: String) -> String? {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "Title cannot be empty.")
        }
        guard let target = note(for: noteID) else { return nil }
        if target.title == trimmed { return nil }

        let newFilename = Note.sanitizedFilename(from: trimmed)
        let lowerNewFilename = newFilename.lowercased()
        let collides = allNotes.contains { other in
            other.id != noteID && other.filename.lowercased() == lowerNewFilename
        }
        if collides {
            return String(localized: "A note named “\(trimmed)” already exists.")
        }
        renameNote(noteID: noteID, newTitle: trimmed)
        return nil
    }

    public func startRename() {
        guard let noteID = selectedNoteID, let note = note(for: noteID) else { return }
        isRenaming = true
        searchQuery = note.title
    }

    public func commitRename() {
        guard isRenaming, let noteID = selectedNoteID, !searchQuery.isEmpty else {
            isRenaming = false
            return
        }
        isRenaming = false
        renameNote(noteID: noteID, newTitle: searchQuery)
        searchQuery = ""
    }

    // MARK: - Wikilink Navigation

    public func navigateToWikilink(title: String) {
        if let current = selectedNoteID {
            snapbackStack.append(current)
        }
        let lowerTitle = title.lowercased()
        if let match = allNotes.first(where: { $0.cachedLowercaseTitle == lowerTitle }) {
            selectedNoteID = match.id
            searchQuery = ""
            filteredNotes = allNotes
        } else {
            searchQuery = title
        }
    }

    public func snapback() {
        guard let previousID = snapbackStack.popLast() else { return }
        selectedNoteID = previousID
        searchQuery = ""
        filteredNotes = allNotes
    }

    // MARK: - Selection

    public func selectNextNote() {
        guard !sortedNotes.isEmpty else { return }
        if let current = selectedNoteID,
           let idx = sortedNotes.firstIndex(where: { $0.id == current }) {
            let nextIdx = sortedNotes.index(after: idx)
            if nextIdx < sortedNotes.endIndex {
                selectedNoteID = sortedNotes[nextIdx].id
            }
        } else {
            selectedNoteID = sortedNotes.first?.id
        }
    }

    public func selectPreviousNote() {
        guard !sortedNotes.isEmpty else { return }
        if let current = selectedNoteID,
           let idx = sortedNotes.firstIndex(where: { $0.id == current }) {
            if idx > sortedNotes.startIndex {
                selectedNoteID = sortedNotes[sortedNotes.index(before: idx)].id
            }
        } else {
            selectedNoteID = sortedNotes.last?.id
        }
    }

    public func deselectNote() {
        if hasSnapback {
            snapback()
        } else {
            selectedNoteID = nil
        }
    }

    // MARK: - Reconcile / Flush

    /// Reconciles the in-memory notes against disk. When `changedPaths` is
    /// given (a batch of FSEvents paths), only those paths are re-read instead
    /// of the whole vault, and `allNotes`/search are only refreshed if
    /// something actually changed (skips self-triggered autosave events).
    /// Pass `nil` to force a full-vault rescan (manual reconcile, or FSEvents
    /// flags that mean the incremental path list can't be trusted).
    public func reconcileFilesystem(changedPaths: [String]? = nil) async {
        guard let store = noteStore else { return }
        if let changedPaths {
            guard !changedPaths.isEmpty else { return }
            let changed = await store.reconcilePaths(changedPaths)
            guard changed else { return }
        } else {
            try? await store.reconcileWithFilesystem()
        }
        allNotes = await store.allNotes()
        await performSearch()
    }

    public func flushBeforeQuit() async {
        bodyUpdateTask?.cancel()
        bodyUpdateTask = nil
        if let pending = pendingBodyUpdate {
            pendingBodyUpdate = nil
            note(for: pending.noteID)?.invalidateSearchCache()
            await noteStore?.updateBody(noteID: pending.noteID, body: pending.body)
        }
        for note in allNotes {
            note.invalidateSearchCache()
        }
        await noteStore?.flushDirtyNotes()
    }

    // MARK: - Import

    public func importNote(_ imported: ImportedNote) {
        Task {
            guard let store = noteStore else { return }
            let note = try? await store.addImportedNote(
                title: imported.title, body: imported.body, tags: imported.tags
            )
            if let note { allNotes.append(note) }
            await performSearch()
        }
    }

    public func createNoteFromIntent(title: String, body: String, tags: [String]) {
        Task {
            guard let store = noteStore else { return }
            let note = try await store.addImportedNote(title: title, body: body, tags: tags)
            allNotes.append(note)
            await performSearch()
            selectedNoteID = note.id
        }
    }

    // MARK: - Bookmarks

    public func saveBookmark() {
        let name = searchQuery.isEmpty ? "Bookmark \(bookmarkStore.bookmarks.count + 1)" : searchQuery
        let bookmark = Bookmark(name: name, searchQuery: searchQuery, noteID: selectedNoteID)
        bookmarkStore.add(bookmark)
    }

    public func restoreBookmark(index: Int) {
        guard let bookmark = bookmarkStore.bookmark(at: index) else { return }
        searchQuery = bookmark.searchQuery
        if let noteID = bookmark.noteID,
           allNotes.contains(where: { $0.id == noteID }) {
            selectedNoteID = noteID
        }
    }

    // MARK: - Batch Tag Ops

    public func batchAddTag(_ tag: String, to noteIDs: Set<UUID>) {
        for noteID in noteIDs {
            guard let note = note(for: noteID) else { continue }
            if !note.tags.contains(tag) {
                var tags = note.tags
                tags.append(tag)
                updateNoteTags(noteID: noteID, tags: tags)
            }
        }
    }

    public func batchRemoveTag(_ tag: String, from noteIDs: Set<UUID>) {
        for noteID in noteIDs {
            guard let note = note(for: noteID) else { continue }
            if note.tags.contains(tag) {
                var tags = note.tags
                tags.removeAll { $0 == tag }
                updateNoteTags(noteID: noteID, tags: tags)
            }
        }
    }

    // MARK: - Sync Status

    public func updateSyncStatus(filename: String, status: SyncStatus) {
        updateSyncStatuses([filename: status])
    }

    /// Applies a batch of filename -> status updates in one pass, instead of
    /// one main-actor hop and one linear `allNotes` scan per file. Only
    /// touches notes whose status actually changed, so unrelated rows don't
    /// get an Observation invalidation on every iCloud metadata tick.
    public func updateSyncStatuses(_ statuses: [String: SyncStatus]) {
        guard !statuses.isEmpty else { return }
        var changed: [String: SyncStatus] = [:]
        for (filename, status) in statuses {
            guard let note = notesByFilename[filename], note.syncStatus != status else { continue }
            note.syncStatus = status
            changed[filename] = status
        }
        guard !changed.isEmpty else { return }
        Task {
            await noteStore?.updateSyncStatuses(changed)
        }
    }

    public var syncHealthSummary: String {
        var uploading = 0, downloading = 0, conflicts = 0
        for note in allNotes {
            switch note.syncStatus {
            case .uploading: uploading += 1
            case .downloading: downloading += 1
            case .conflict: conflicts += 1
            default: break
            }
        }

        if conflicts > 0 {
            return "\(conflicts) conflict\(conflicts == 1 ? "" : "s")"
        }
        if uploading > 0 && downloading > 0 {
            return "Uploading \(uploading), downloading \(downloading)"
        }
        if uploading > 0 {
            return "Uploading \(uploading) note\(uploading == 1 ? "" : "s")"
        }
        if downloading > 0 {
            return "Downloading \(downloading) note\(downloading == 1 ? "" : "s")"
        }
        return "All synced"
    }

    // MARK: - URL Scheme

    public func handleURL(_ url: URL) {
        guard let action = URLSchemeHandler.parse(url) else { return }

        switch action.kind {
        case .find(let searchTerm, let noteID):
            if let current = selectedNoteID {
                snapbackStack.append(current)
            }

            if let noteID, let match = allNotes.first(where: { $0.id == noteID }) {
                selectedNoteID = match.id
                searchQuery = ""
                filteredNotes = allNotes
            } else if !searchTerm.isEmpty {
                searchQuery = searchTerm
                if let match = SearchEngine.exactTitleMatch(notes: allNotes, query: searchTerm) {
                    selectedNoteID = match.id
                }
            }

            onURLActivation?()

        case .make(let title, let body, let tags):
            let noteTitle = title ?? "Untitled"
            Task {
                guard let store = noteStore else { return }
                let note = try await store.addImportedNote(
                    title: noteTitle,
                    body: body ?? "",
                    tags: tags
                )
                allNotes.append(note)
                await performSearch()
                selectedNoteID = note.id
            }
            onURLActivation?()
        }
    }

    // MARK: - Storage Service Access (for ImportExportService consumers)

    /// Used by app-shell layer code that needs raw storage (e.g. import/export
    /// flows that resolve filenames or work with the FileStorageService actor).
    public var storage: FileStorageService? { storageService }

    /// Imported notes batch-add. Called by macOS file/directory/pasteboard
    /// import paths that already produced `ImportedNote` values.
    public func importNotes(_ notes: [ImportedNote]) {
        Task {
            guard let store = noteStore else { return }
            for item in notes {
                if let note = try? await store.addImportedNote(
                    title: item.title, body: item.body, tags: item.tags
                ) {
                    allNotes.append(note)
                }
            }
            await performSearch()
        }
    }
}
