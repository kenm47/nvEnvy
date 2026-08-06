import Foundation

public actor NoteStore {
    private var notes: [UUID: Note] = [:]
    private var filenameIndex: [String: UUID] = [:]
    private var dirtyNoteIDs: Set<UUID> = []
    private let storage: FileStorageService
    private var flushTask: Task<Void, Never>?
    private let flushInterval: Duration = .seconds(2)
    private let crashRecovery: CrashRecoveryService

    public init(storage: FileStorageService, crashRecovery: CrashRecoveryService? = nil) {
        self.storage = storage
        self.crashRecovery = crashRecovery ?? CrashRecoveryService()
    }

    // MARK: - Load

    private func indexNote(_ note: Note) {
        filenameIndex[note.filename] = note.id
    }

    private func unindexNote(_ note: Note) {
        filenameIndex.removeValue(forKey: note.filename)
    }

    public func loadAll() async throws {
        let loaded = try await storage.readAllNotes()
        for note in loaded {
            notes[note.id] = note
            indexNote(note)
        }

        // Recover any pending WAL entries from a previous crash
        if let recovered = try? await crashRecovery.recoverPendingNotes(), !recovered.isEmpty {
            for rec in recovered {
                if let existing = notes[rec.noteID] {
                    // Only apply if WAL is newer
                    if rec.timestamp > existing.modifiedDate {
                        existing.title = rec.title
                        existing.body = rec.body
                        existing.tags = rec.tags
                        existing.modifiedDate = rec.timestamp
                        existing.invalidateSearchCache()
                        dirtyNoteIDs.insert(rec.noteID)
                    }
                } else {
                    // Note not on disk yet — recreate from WAL
                    let note = Note(
                        id: rec.noteID,
                        title: rec.title,
                        body: rec.body,
                        tags: rec.tags,
                        modifiedDate: rec.timestamp
                    )
                    notes[note.id] = note
                    indexNote(note)
                    dirtyNoteIDs.insert(note.id)
                }
            }
            // Flush recovered notes to disk
            await flushDirtyNotes()
        }
    }

    // MARK: - CRUD

    public func allNotes() -> [Note] {
        Array(notes.values)
    }

    public func note(for id: UUID) -> Note? {
        notes[id]
    }

    public func createNote(title: String) async throws -> Note {
        let sanitized = Note.sanitizedFilename(from: title)
        let uniqueName = await storage.ensureUniqueFilename(sanitized)
        let note = Note(title: title, filename: uniqueName)
        notes[note.id] = note
        indexNote(note)
        markDirty(note.id)
        return note
    }

    public func addImportedNote(title: String, body: String, tags: [String]) async throws -> Note {
        let sanitized = Note.sanitizedFilename(from: title)
        let uniqueName = await storage.ensureUniqueFilename(sanitized)
        let note = Note(title: title, body: body, tags: tags, filename: uniqueName)
        notes[note.id] = note
        indexNote(note)
        markDirty(note.id)
        return note
    }

    /// Applies `body` and marks the note dirty.
    ///
    /// `Note` is a reference type shared with the view model, which mutates it
    /// before calling here, so in practice this assignment is a no-op. It is
    /// still done: a setter that silently ignores its own argument is a trap for
    /// every other caller, and leaves the value that gets persisted depending on
    /// whether the caller happened to mutate the shared object first.
    public func updateBody(noteID: UUID, body: String) {
        guard let note = notes[noteID] else { return }
        note.body = body
        note.modifiedDate = Date()
        note.invalidateSearchCache()
        markDirty(noteID)
    }

    /// Applies `tags` and marks the note dirty. See `updateBody` on why this
    /// assigns rather than relying on the caller having mutated the note.
    public func updateTags(noteID: UUID, tags: [String]) {
        guard let note = notes[noteID] else { return }
        note.tags = tags
        note.modifiedDate = Date()
        note.invalidateSearchCache()
        markDirty(noteID)
    }

    public func updateTitle(noteID: UUID, title: String) async throws {
        guard let note = notes[noteID] else { return }
        let oldFilename = note.filename
        unindexNote(note)
        note.title = title
        note.filename = Note.sanitizedFilename(from: title)
        note.modifiedDate = Date()
        note.invalidateSearchCache()
        indexNote(note)
        try await storage.renameNote(note, oldFilename: oldFilename)
        markDirty(noteID)
    }

    public func deleteNote(noteID: UUID) async throws {
        guard let note = notes[noteID] else { return }
        try await storage.deleteNote(note)
        unindexNote(note)
        notes.removeValue(forKey: noteID)
        dirtyNoteIDs.remove(noteID)
    }

    // MARK: - Sync Status

    public func updateSyncStatus(filename: String, status: SyncStatus) {
        guard let id = filenameIndex[filename], let note = notes[id] else { return }
        note.syncStatus = status
    }

    /// One actor hop for a batch of filename -> status updates, instead of a
    /// separate `Task` per changed file.
    public func updateSyncStatuses(_ statuses: [String: SyncStatus]) {
        for (filename, status) in statuses {
            guard let id = filenameIndex[filename], let note = notes[id] else { continue }
            note.syncStatus = status
        }
    }

    // MARK: - Dirty Tracking & Flush

    public func markDirty(_ noteID: UUID) {
        dirtyNoteIDs.insert(noteID)
        if let note = notes[noteID] {
            Task {
                try? await self.crashRecovery.appendRecord(note: note)
            }
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.flushDirtyNotes()
        }
    }

    public func flushDirtyNotes() async {
        let ids = dirtyNoteIDs
        dirtyNoteIDs.removeAll()

        var anyFailed = false
        for id in ids {
            guard let note = notes[id] else { continue }
            do {
                try await storage.writeNote(note)
            } catch {
                // Re-mark as dirty on failure
                dirtyNoteIDs.insert(id)
                anyFailed = true
            }
        }

        // Truncate WAL only if all dirty notes flushed successfully
        if !anyFailed {
            try? await crashRecovery.truncate()
        }
    }

    public var hasDirtyNotes: Bool {
        !dirtyNoteIDs.isEmpty
    }

    // MARK: - External Change Reconciliation

    public func reconcileWithFilesystem() async throws {
        let fileNotes = try await storage.readAllNotes()
        var fileByName: [String: Note] = [:]
        for fn in fileNotes {
            fileByName[fn.filename] = fn
        }

        // Detect new and modified files
        for (filename, fileNote) in fileByName {
            if let existingID = filenameIndex[filename], let existing = notes[existingID] {
                // Check if file is newer
                if let fileMod = fileNote.fileModifiedDate,
                   let existMod = existing.fileModifiedDate,
                   fileMod > existMod {
                    existing.body = fileNote.body
                    existing.tags = fileNote.tags
                    existing.modifiedDate = fileNote.modifiedDate
                    existing.fileModifiedDate = fileMod
                    existing.fileSize = fileNote.fileSize
                    existing.invalidateSearchCache()
                }
            } else {
                // New file
                notes[fileNote.id] = fileNote
                indexNote(fileNote)
            }
        }

        // Detect deleted files
        let fileNames = Set(fileByName.keys)
        let toRemove = notes.values.filter { !fileNames.contains($0.filename) }
        for note in toRemove {
            unindexNote(note)
            notes.removeValue(forKey: note.id)
        }
    }

    /// Reconciles only the given absolute file paths (from an FSEvents batch)
    /// instead of re-reading the whole vault. Returns whether anything actually
    /// changed, so the caller can skip reassigning its notes snapshot when
    /// nothing did (e.g. the events were all our own autosaves).
    public func reconcilePaths(_ absolutePaths: [String]) async -> Bool {
        var changed = false
        var seenFilenames = Set<String>()

        for path in absolutePaths {
            guard let filename = await storage.filename(forPath: path) else { continue }
            guard seenFilenames.insert(filename).inserted else { continue }

            let url = URL(fileURLWithPath: path)
            let existingID = filenameIndex[filename]
            let existing = existingID.flatMap { notes[$0] }

            guard await storage.fileExists(at: url) else {
                // Deleted (or never-existed) file.
                if let existing {
                    unindexNote(existing)
                    notes.removeValue(forKey: existing.id)
                    changed = true
                }
                continue
            }

            if await storage.wasSelfWrite(path: path) {
                continue
            }

            guard let stat = await storage.statFile(at: url) else { continue }
            if let existing {
                if existing.fileModifiedDate == stat.modDate && existing.fileSize == stat.size {
                    continue // no real change
                }
                guard let fresh = await storage.loadSingleNote(at: url) else { continue }
                existing.body = fresh.body
                existing.tags = fresh.tags
                existing.title = fresh.title
                existing.modifiedDate = fresh.modifiedDate
                existing.fileModifiedDate = fresh.fileModifiedDate
                existing.fileSize = fresh.fileSize
                existing.invalidateSearchCache()
                changed = true
            } else {
                guard let fresh = await storage.loadSingleNote(at: url) else { continue }
                notes[fresh.id] = fresh
                indexNote(fresh)
                changed = true
            }
        }

        return changed
    }
}
