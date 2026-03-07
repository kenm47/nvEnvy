import XCTest
@testable import NvEnvyCore

final class IntegrationTests: XCTestCase {
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

    // MARK: - End-to-End Flows

    func testCreateNoteAppearsInSearch() async throws {
        let note = try await store.createNote(title: "Integration Test Note")
        var engine = SearchEngine()
        let allNotes = await store.allNotes()
        let results = engine.filter(notes: allNotes, query: "integration")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Integration Test Note")
    }

    func testModifyFlushReread() async throws {
        let note = try await store.createNote(title: "Modify Test")
        await store.updateBody(noteID: note.id, body: "Updated content here")
        await store.flushDirtyNotes()

        // Create a new store from the same directory and re-read
        let store2 = NoteStore(storage: storage)
        try await store2.loadAll()
        let allNotes = await store2.allNotes()
        let found = allNotes.first { $0.title == "Modify Test" }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.body, "Updated content here")
    }

    func testImportFileAppearsInStore() async throws {
        let file = tempDir.appendingPathComponent("imported.md")
        try "# Imported\n\nImported body text".write(to: file, atomically: true, encoding: .utf8)

        let service = ImportExportService()
        let imported = try await service.importFile(at: file)
        let note = try await store.addImportedNote(title: imported.title, body: imported.body, tags: imported.tags)

        let allNotes = await store.allNotes()
        XCTAssertTrue(allNotes.contains { $0.id == note.id })
        XCTAssertEqual(note.body, "# Imported\n\nImported body text")
    }

    func testWALRecovery() async throws {
        let walDir = tempDir.appendingPathComponent("wal-test-cache")
        try FileManager.default.createDirectory(at: walDir, withIntermediateDirectories: true)
        let crashRecovery = CrashRecoveryService(cacheDirectory: walDir)

        let store1 = NoteStore(storage: storage, crashRecovery: crashRecovery)
        let note = try await store1.createNote(title: "WAL Test")
        await store1.updateBody(noteID: note.id, body: "This should be recovered")
        // Don't flush — simulate crash

        // Create a new store with same storage and WAL
        let store2 = NoteStore(storage: storage, crashRecovery: crashRecovery)
        try await store2.loadAll()
        let allNotes = await store2.allNotes()
        let recovered = allNotes.first { $0.title == "WAL Test" }
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.body, "This should be recovered")
    }

    func testBatchTagAdd() async throws {
        var notes: [Note] = []
        for i in 0..<5 {
            let note = try await store.createNote(title: "Batch \(i)")
            notes.append(note)
        }

        // Batch add tag
        for note in notes {
            var tags = note.tags
            if !tags.contains("batch-tag") {
                tags.append("batch-tag")
                await store.updateTags(noteID: note.id, tags: tags)
            }
        }

        // Verify all have the tag
        for note in notes {
            let updated = await store.note(for: note.id)!
            XCTAssertTrue(updated.tags.contains("batch-tag"), "Note \(updated.title) should have batch-tag")
        }
    }

    // MARK: - Search Edge Cases

    func testEmptyQueryReturnsAllNotes() async throws {
        _ = try await store.createNote(title: "Note A")
        _ = try await store.createNote(title: "Note B")
        var engine = SearchEngine()
        let results = engine.filter(notes: await store.allNotes(), query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSingleCharacterQuery() async throws {
        let note = try await store.createNote(title: "X Marks the Spot")
        var engine = SearchEngine()
        let results = engine.filter(notes: [note], query: "x")
        XCTAssertEqual(results.count, 1)
    }

    func testSpacesOnlyQuery() {
        var engine = SearchEngine()
        let notes = [Note(title: "Test")]
        let results = engine.filter(notes: notes, query: "   ")
        // Spaces-only should produce empty tokens, returning all notes
        XCTAssertEqual(results.count, 1)
    }

    func testVeryLongQuery() {
        var engine = SearchEngine()
        let longQuery = String(repeating: "a", count: 1000)
        let notes = [Note(title: "Short")]
        let results = engine.filter(notes: notes, query: longQuery)
        XCTAssertEqual(results.count, 0)
    }

    func testSpecialCharactersInQuery() {
        var engine = SearchEngine()
        let notes = [
            Note(title: "C++ Programming"),
            Note(title: "C# Guide"),
            Note(title: "Plain Note"),
        ]
        let results = engine.filter(notes: notes, query: "c++")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "C++ Programming")
    }

    // MARK: - FrontmatterParser Round-Trip

    func testRoundTripWithTags() {
        let original = "---\ntags:\n  - swift\n  - mac\n---\nSome body"
        let parsed = FrontmatterParser.parse(original)
        let serialized = FrontmatterParser.serialize(
            frontmatter: parsed.frontmatter,
            body: parsed.body
        )
        let reparsed = FrontmatterParser.parse(serialized)
        XCTAssertEqual(parsed.body, reparsed.body)
        XCTAssertEqual(parsed.frontmatter?.tags, reparsed.frontmatter?.tags)
    }

    func testRoundTripNoFrontmatter() {
        let original = "Just plain text without frontmatter"
        let parsed = FrontmatterParser.parse(original)
        XCTAssertNil(parsed.frontmatter)
        XCTAssertEqual(parsed.body, original)
    }

    func testRoundTripUnknownKeys() {
        let original = "---\ntags:\n  - test\ncustom_key: custom_value\n---\nBody"
        let parsed = FrontmatterParser.parse(original)
        let serialized = FrontmatterParser.serialize(
            frontmatter: parsed.frontmatter,
            body: parsed.body
        )
        let reparsed = FrontmatterParser.parse(serialized)
        XCTAssertEqual(parsed.body, reparsed.body)
        XCTAssertEqual(parsed.frontmatter?.tags, reparsed.frontmatter?.tags)
    }

    func testRoundTripEmptyTags() {
        let original = "---\ntags: []\n---\nBody with empty tags"
        let parsed = FrontmatterParser.parse(original)
        let serialized = FrontmatterParser.serialize(
            frontmatter: parsed.frontmatter,
            body: parsed.body
        )
        let reparsed = FrontmatterParser.parse(serialized)
        XCTAssertEqual(reparsed.body, "Body with empty tags")
    }

    func testRoundTripUnicode() {
        let original = "---\ntags:\n  - 日本語\n  - émojis\n---\nUnicode body: 🎉 中文"
        let parsed = FrontmatterParser.parse(original)
        let serialized = FrontmatterParser.serialize(
            frontmatter: parsed.frontmatter,
            body: parsed.body
        )
        let reparsed = FrontmatterParser.parse(serialized)
        XCTAssertEqual(parsed.body, reparsed.body)
        XCTAssertEqual(parsed.frontmatter?.tags, reparsed.frontmatter?.tags)
        XCTAssertTrue(reparsed.body.contains("🎉"))
        XCTAssertTrue(reparsed.body.contains("中文"))
    }
}
