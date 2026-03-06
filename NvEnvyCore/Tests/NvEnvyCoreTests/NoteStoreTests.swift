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
        store = NoteStore(storage: storage)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCreateNote() async throws {
        let note = try await store.createNote(title: "Test Note")
        XCTAssertEqual(note.title, "Test Note")
        XCTAssertFalse(note.filename.isEmpty)
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
}
