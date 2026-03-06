import Foundation

public actor NoteStore {
    private var notes: [UUID: Note] = [:]
    private var dirtyNoteIDs: Set<UUID> = []
    private let storage: FileStorageService
    private var flushTask: Task<Void, Never>?
    private let flushInterval: Duration = .seconds(2)

    public init(storage: FileStorageService) {
        self.storage = storage
    }

    // MARK: - Load

    public func loadAll() async throws {
        let loaded = try await storage.readAllNotes()
        for note in loaded {
            notes[note.id] = note
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
        markDirty(note.id)
        return note
    }

    public func updateBody(noteID: UUID, body: String) {
        guard let note = notes[noteID] else { return }
        note.body = body
        note.modifiedDate = Date()
        note.invalidateSearchCache()
        markDirty(noteID)
    }

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
        note.title = title
        note.filename = Note.sanitizedFilename(from: title)
        note.modifiedDate = Date()
        note.invalidateSearchCache()
        try await storage.renameNote(note, oldFilename: oldFilename)
        markDirty(noteID)
    }

    public func deleteNote(noteID: UUID) async throws {
        guard let note = notes[noteID] else { return }
        try await storage.deleteNote(note)
        notes.removeValue(forKey: noteID)
        dirtyNoteIDs.remove(noteID)
    }

    // MARK: - Dirty Tracking & Flush

    public func markDirty(_ noteID: UUID) {
        dirtyNoteIDs.insert(noteID)
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

        for id in ids {
            guard let note = notes[id] else { continue }
            do {
                try await storage.writeNote(note)
            } catch {
                // Re-mark as dirty on failure
                dirtyNoteIDs.insert(id)
            }
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
            if let existing = notes.values.first(where: { $0.filename == filename }) {
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
            }
        }

        // Detect deleted files
        let fileNames = Set(fileByName.keys)
        let toRemove = notes.values.filter { !fileNames.contains($0.filename) }
        for note in toRemove {
            notes.removeValue(forKey: note.id)
        }
    }
}
