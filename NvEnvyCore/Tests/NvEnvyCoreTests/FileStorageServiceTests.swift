import XCTest
@testable import NvEnvyCore

final class FileStorageServiceTests: XCTestCase {
    var tempDir: URL!
    var storage: FileStorageService!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storage = FileStorageService(notesDirectory: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWriteAndReadNote() async throws {
        let note = Note(title: "Test Note", body: "Hello world", tags: ["swift"])
        try await storage.writeNote(note)

        let url = await storage.fileURL(for: note)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let parsed = try await storage.readNote(at: url)
        XCTAssertEqual(parsed.body, "Hello world")
        XCTAssertEqual(parsed.frontmatter?.tags, ["swift"])
    }

    func testReadAllNotes() async throws {
        // Write two files manually
        let file1 = tempDir.appendingPathComponent("Note One.md")
        let file2 = tempDir.appendingPathComponent("Note Two.md")
        try "---\ntags:\n  - test\n---\nBody one".write(to: file1, atomically: true, encoding: .utf8)
        try "Body two".write(to: file2, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 2)

        let noteOne = notes.first { $0.title == "Note One" }
        XCTAssertNotNil(noteOne)
        XCTAssertEqual(noteOne?.tags, ["test"])
        XCTAssertEqual(noteOne?.body, "Body one")
    }

    func testDeleteNote() async throws {
        let note = Note(title: "To Delete", body: "content")
        try await storage.writeNote(note)

        let url = await storage.fileURL(for: note)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try await storage.deleteNote(note)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAtomicWrite() async throws {
        let note = Note(title: "Atomic Test", body: "Initial")
        try await storage.writeNote(note)

        // Overwrite
        note.body = "Updated"
        try await storage.writeNote(note)

        let url = await storage.fileURL(for: note)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("Updated"))
    }

    func testUniqueFilename() async throws {
        let file = tempDir.appendingPathComponent("Duplicate.md")
        try "existing".write(to: file, atomically: true, encoding: .utf8)

        let unique = await storage.ensureUniqueFilename("Duplicate")
        XCTAssertEqual(unique, "Duplicate 2")
    }

    func testNonMdFilesIgnored() async throws {
        let txtFile = tempDir.appendingPathComponent("note.txt")
        try "text note".write(to: txtFile, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 0)
    }
}
