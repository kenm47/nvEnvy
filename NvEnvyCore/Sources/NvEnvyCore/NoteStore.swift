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

    public func updateBody(noteID: UUID, body: String) {
        guard notes[noteID] != nil else { return }
        // Note is a reference type shared with AppState — already mutated by caller
        markDirty(noteID)
    }

    public func updateTags(noteID: UUID, tags: [String]) {
        guard notes[noteID] != nil else { return }
        // Note is a reference type shared with AppState — already mutated by caller
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
}
