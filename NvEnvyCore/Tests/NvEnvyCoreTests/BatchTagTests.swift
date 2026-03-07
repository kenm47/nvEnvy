import XCTest
@testable import NvEnvyCore

final class BatchTagTests: XCTestCase {
    var tempDir: URL!
    var store: NoteStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storage = FileStorageService(notesDirectory: tempDir)
        store = NoteStore(storage: storage)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testBatchUpdateTags() async throws {
        let note1 = try await store.createNote(title: "Note 1")
        let note2 = try await store.createNote(title: "Note 2")

        await store.updateTags(noteID: note1.id, tags: ["existing"])
        await store.updateTags(noteID: note2.id, tags: ["other"])

        // Simulate batch add: add "shared" to both
        for noteID in [note1.id, note2.id] {
            let note = await store.note(for: noteID)!
            var tags = note.tags
            if !tags.contains("shared") {
                tags.append("shared")
                await store.updateTags(noteID: noteID, tags: tags)
            }
        }

        let n1 = await store.note(for: note1.id)!
        let n2 = await store.note(for: note2.id)!
        XCTAssertTrue(n1.tags.contains("shared"))
        XCTAssertTrue(n2.tags.contains("shared"))
        XCTAssertTrue(n1.tags.contains("existing"))
        XCTAssertTrue(n2.tags.contains("other"))
    }

    func testBatchRemoveTags() async throws {
        let note1 = try await store.createNote(title: "Note 1")
        let note2 = try await store.createNote(title: "Note 2")

        await store.updateTags(noteID: note1.id, tags: ["remove-me", "keep"])
        await store.updateTags(noteID: note2.id, tags: ["remove-me", "also-keep"])

        // Simulate batch remove
        for noteID in [note1.id, note2.id] {
            let note = await store.note(for: noteID)!
            var tags = note.tags
            tags.removeAll { $0 == "remove-me" }
            await store.updateTags(noteID: noteID, tags: tags)
        }

        let n1 = await store.note(for: note1.id)!
        let n2 = await store.note(for: note2.id)!
        XCTAssertFalse(n1.tags.contains("remove-me"))
        XCTAssertFalse(n2.tags.contains("remove-me"))
        XCTAssertTrue(n1.tags.contains("keep"))
        XCTAssertTrue(n2.tags.contains("also-keep"))
    }
}
