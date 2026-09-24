import XCTest
@testable import NvEnvyCore

final class NoteStoreTests: XCTestCase {
    var tempDir: URL!
    var storage: FileStorageService!
    var store: NoteStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storage = FileStorageService(notesDirectory: tempDir)
        // Give this NoteStore its own WAL directory instead of the default
        // CrashRecoveryService's fixed shared path -- under
        // `swift test --parallel` multiple test processes writing/truncating
        // the same WAL file race each other.
        let crashRecovery = CrashRecoveryService(cacheDirectory: tempDir.appendingPathComponent("wal-cache"))
        store = NoteStore(storage: storage, crashRecovery: crashRecovery)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCreateNote() async throws {
        let note = try await store.createNote(title: "Test Note")
        XCTAssertEqual(note.title, "Test Note")
        XCTAssertTrue(note.filename.hasSuffix(".md"))
    }

    func testCreateNoteWithDuplicateTitlesGetsDistinctFilenames() async throws {
        // Regression: two notes created with the same title before either was
        // flushed to disk used to both resolve to "Untitled.md" — the old
        // `ensureUniqueFilename` only checked the filesystem, not notes
        // already created in memory. That crashed the launch-time index build
        // the same way an on-disk `Ideas.md`/`Ideas.txt` collision did.
        let a = try await store.createNote(title: "Untitled")
        let b = try await store.createNote(title: "Untitled")
        XCTAssertNotEqual(a.filename, b.filename)
        XCTAssertEqual(a.filename, "Untitled.md")
        XCTAssertEqual(b.filename, "Untitled 2.md")
    }

    func testRenamePreservesSubfolderAndExtension() async throws {
        let dailyDir = tempDir.appendingPathComponent("Daily")
        try FileManager.default.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        try "x".write(to: dailyDir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)

        try await store.loadAll()
        // `.first(where:)` rather than `.first!`: `NoteStore`'s default
        // `CrashRecoveryService` uses a shared (non-test-scoped) cache
        // directory, so a WAL entry left behind by another test in the same
        // process can otherwise show up in `allNotes()` too.
        let allNotes = await store.allNotes()
        let note = try XCTUnwrap(allNotes.first { $0.filename == "Daily/log.txt" })

        try await store.updateTitle(noteID: note.id, title: "Journal")

        XCTAssertEqual(note.filename, "Daily/Journal.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dailyDir.appendingPathComponent("Journal.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Journal.md").path))
    }

    func testRenameToSameSanitizedNameKeepsExistingFile() async throws {
        // `sanitizedFilename` maps both "hello:world" and "hello/world" to
        // "hello-world" (forbidden characters -> "-"). Renaming between two
        // titles that land on the same sanitized name must not treat the
        // note's own on-disk file as a collision and bump it to " 2".
        let note = try await store.createNote(title: "hello:world")
        await store.flushDirtyNotes()
        XCTAssertEqual(note.filename, "hello-world.md")
        try await store.updateTitle(noteID: note.id, title: "hello/world")
        XCTAssertEqual(note.filename, "hello-world.md")
    }

    func testAllNotes() async throws {
        _ = try await store.createNote(title: "Note 1")
        _ = try await store.createNote(title: "Note 2")
        let all = await store.allNotes()
        XCTAssertEqual(all.count, 2)
    }

    func testUpdateBody() async throws {
        let note = try await store.createNote(title: "Test")
        await store.updateBody(noteID: note.id, body: "Updated body")
        let fetched = await store.note(for: note.id)
        XCTAssertEqual(fetched?.body, "Updated body")
    }

    func testDeleteNote() async throws {
        let note = try await store.createNote(title: "To Delete")
        await store.flushDirtyNotes()
        try await store.deleteNote(noteID: note.id)
        let fetched = await store.note(for: note.id)
        XCTAssertNil(fetched)
    }

    func testFlushWritesFiles() async throws {
        let note = try await store.createNote(title: "Flush Test")
        await store.updateBody(noteID: note.id, body: "Some content")
        await store.flushDirtyNotes()

        let fileURL = tempDir.appendingPathComponent("Flush Test.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Some content"))
    }

    func testDirtyTracking() async throws {
        let note = try await store.createNote(title: "Dirty")
        let hasDirty = await store.hasDirtyNotes
        XCTAssertTrue(hasDirty)

        await store.flushDirtyNotes()
        let hasDirtyAfter = await store.hasDirtyNotes
        XCTAssertFalse(hasDirtyAfter)
    }

    // MARK: - Unknown frontmatter across external edits

    /// Writes a note whose frontmatter carries a key nvEnvy doesn't model, with
    /// an explicit mtime so reconciliation sees successive writes as newer.
    private func writeExternally(_ url: URL, externalID: String, body: String, mtime: Date) throws {
        try """
        ---
        id: \(externalID)
        ---
        \(body)
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    /// An external tool rewriting a note's unknown frontmatter (Joplin assigning
    /// or changing its `id`) must be picked up when the in-memory note is
    /// refreshed, or the next save writes the stale keys back over it.
    private func assertExternalFrontmatterSurvivesSave(
        reconcile: (URL) async throws -> Void
    ) async throws {
        let file = tempDir.appendingPathComponent("Reconciled.md")
        let start = Date(timeIntervalSinceNow: -60)
        try writeExternally(file, externalID: "aaaa0000", body: "First", mtime: start)
        try await store.loadAll()
        let loaded = await store.allNotes()
        let note = try XCTUnwrap(loaded.first)

        try writeExternally(file, externalID: "bbbb1111-changed", body: "Second",
                            mtime: start.addingTimeInterval(30))
        try await reconcile(file)
        XCTAssertEqual(note.body, "Second")

        note.body = "Edited in nvEnvy"
        await store.updateBody(noteID: note.id, body: note.body)
        await store.flushDirtyNotes()

        let written = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(written.contains("id: bbbb1111-changed"),
                      "External frontmatter change was reverted on save:\n\(written)")
        XCTAssertFalse(written.contains("aaaa0000"), written)
        XCTAssertTrue(written.contains("Edited in nvEnvy"))
    }

    func testReconcilePathsPicksUpExternalUnknownFrontmatter() async throws {
        try await assertExternalFrontmatterSurvivesSave { url in
            _ = await self.store.reconcilePaths([url.path])
        }
    }

    func testReconcileWithFilesystemPicksUpExternalUnknownFrontmatter() async throws {
        try await assertExternalFrontmatterSurvivesSave { _ in
            try await self.store.reconcileWithFilesystem()
        }
    }
}
