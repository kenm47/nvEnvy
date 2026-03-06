import XCTest
@testable import NvEnvyCore

final class TagTests: XCTestCase {

    func testNoteTagsRoundTrip() {
        let note = Note(title: "Tagged Note", tags: ["swift", "macos"])
        XCTAssertEqual(note.tags, ["swift", "macos"])
        XCTAssertTrue(note.cachedLowercaseTags.contains("swift"))
        XCTAssertTrue(note.cachedLowercaseTags.contains("macos"))
    }

    func testTagAddRemove() {
        let note = Note(title: "Test")
        XCTAssertTrue(note.tags.isEmpty)

        note.tags.append("new-tag")
        note.invalidateSearchCache()
        XCTAssertEqual(note.tags, ["new-tag"])
        XCTAssertTrue(note.cachedLowercaseTags.contains("new-tag"))

        note.tags.removeAll { $0 == "new-tag" }
        note.invalidateSearchCache()
        XCTAssertTrue(note.tags.isEmpty)
        XCTAssertTrue(note.cachedLowercaseTags.isEmpty)
    }

    func testTagSearchFiltering() {
        var engine = SearchEngine()
        let notes = [
            Note(title: "Note A", tags: ["project", "urgent"]),
            Note(title: "Note B", tags: ["personal"]),
            Note(title: "Note C", tags: ["project"]),
        ]

        let results = engine.filter(notes: notes, query: "project")
        XCTAssertEqual(results.count, 2)
    }

    func testTagsInFrontmatter() {
        let content = "---\ntags:\n  - alpha\n  - beta\n  - gamma\n---\nBody"
        let parsed = FrontmatterParser.parse(content)
        XCTAssertEqual(parsed.frontmatter?.tags, ["alpha", "beta", "gamma"])

        // Serialize back
        let serialized = FrontmatterParser.serialize(frontmatter: parsed.frontmatter, body: parsed.body)
        XCTAssertTrue(serialized.contains("  - alpha"))
        XCTAssertTrue(serialized.contains("  - beta"))
        XCTAssertTrue(serialized.contains("  - gamma"))

        // Re-parse
        let reparsed = FrontmatterParser.parse(serialized)
        XCTAssertEqual(reparsed.frontmatter?.tags, ["alpha", "beta", "gamma"])
        XCTAssertEqual(reparsed.body, "Body")
    }

    func testEmptyTagsRemoveFrontmatter() {
        let fm = FrontmatterBlock(tags: [])
        let serialized = FrontmatterParser.serialize(frontmatter: fm, body: "Just body")
        XCTAssertEqual(serialized, "Just body")
    }

    func testTagUpdatePreservesOtherFields() {
        let content = "---\ntags:\n  - old\naliases: test\n---\nBody"
        var parsed = FrontmatterParser.parse(content)
        parsed.frontmatter?.tags = ["new1", "new2"]
        let serialized = FrontmatterParser.serialize(frontmatter: parsed.frontmatter, body: parsed.body)

        let reparsed = FrontmatterParser.parse(serialized)
        XCTAssertEqual(reparsed.frontmatter?.tags, ["new1", "new2"])
        XCTAssertEqual(reparsed.frontmatter?.unknownFields.count, 1)
        XCTAssertEqual(reparsed.frontmatter?.unknownFields[0].key, "aliases")
    }

    func testNoteStoreUpdateTags() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = FileStorageService(notesDirectory: tempDir)
        let store = NoteStore(storage: storage)
        let note = try await store.createNote(title: "Tag Test")

        await store.updateTags(noteID: note.id, tags: ["a", "b"])
        let fetched = await store.note(for: note.id)
        XCTAssertEqual(fetched?.tags, ["a", "b"])
    }
}
