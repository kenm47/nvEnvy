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

        let result = try await storage.readNote(at: url)
        XCTAssertEqual(result.parsed.body, "Hello world")
        XCTAssertEqual(result.parsed.frontmatter?.tags, ["swift"])
    }

    /// Frontmatter keys nvEnvy doesn't model must survive a read/edit/write
    /// cycle. Joplin's two-way sync keys note identity on `id`, so dropping it
    /// makes an edited note look brand new and get re-imported as a duplicate.
    ///
    /// This deliberately goes through readAllNotes/writeNote rather than
    /// FrontmatterParser alone — the parser round-trips unknown keys fine, and
    /// testing it in isolation is what let the write path lose them unnoticed.
    func testUnknownFrontmatterKeysSurviveWrite() async throws {
        let file = tempDir.appendingPathComponent("test nveny.md")
        try """
        ---
        id: ef6e5d5434a5453cace6e8553ae85bb3
        title: test nveny
        tags:
          - radar
        created: 2026-08-06T07:11:00Z
        modified: 2026-08-06T10:56:32Z
        ---
        Original body
        """.write(to: file, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        let note = try XCTUnwrap(notes.first)
        XCTAssertEqual(note.unknownFrontmatterFields.count, 2)

        note.body = "Edited body"
        try await storage.writeNote(note)

        let written = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(written.contains("id: ef6e5d5434a5453cace6e8553ae85bb3"),
                      "Joplin's note id was dropped on save:\n\(written)")
        XCTAssertTrue(written.contains("title: test nveny"),
                      "Unknown key `title` was dropped on save:\n\(written)")
        XCTAssertTrue(written.contains("Edited body"))

        // And the keys must still be there after a second cycle, not just the first.
        let reread = try await storage.readAllNotes()
        XCTAssertEqual(try XCTUnwrap(reread.first).unknownFrontmatterFields.count, 2)
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

    func testNonAllowedFilesIgnored() async throws {
        let logFile = tempDir.appendingPathComponent("note.log")
        try "log note".write(to: logFile, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 0)
    }

    // MARK: - Recursive Folder Reading

    func testRecursiveSubdirectoryRead() async throws {
        // Root note
        let root = tempDir.appendingPathComponent("Root Note.md")
        try "Root body".write(to: root, atomically: true, encoding: .utf8)

        // Subdirectory note
        let subDir = tempDir.appendingPathComponent("subfolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let subNote = subDir.appendingPathComponent("Sub Note.md")
        try "Sub body".write(to: subNote, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 2)

        let rootNote = notes.first { $0.title == "Root Note" }
        XCTAssertNotNil(rootNote)
        XCTAssertEqual(rootNote?.body, "Root body")
        XCTAssertEqual(rootNote?.filename, "Root Note")

        let subFolderNote = notes.first { $0.title == "Sub Note" }
        XCTAssertNotNil(subFolderNote)
        XCTAssertEqual(subFolderNote?.body, "Sub body")
        XCTAssertEqual(subFolderNote?.filename, "subfolder/Sub Note")
    }

    func testObsidianDirIgnored() async throws {
        // .obsidian directory should be skipped
        let obsDir = tempDir.appendingPathComponent(".obsidian")
        try FileManager.default.createDirectory(at: obsDir, withIntermediateDirectories: true)
        let obsNote = obsDir.appendingPathComponent("workspace.md")
        try "workspace data".write(to: obsNote, atomically: true, encoding: .utf8)

        // Regular note
        let note = tempDir.appendingPathComponent("Real Note.md")
        try "Real content".write(to: note, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Real Note")
    }

    func testHiddenDirectoriesSkipped() async throws {
        let hiddenDir = tempDir.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        let hiddenNote = hiddenDir.appendingPathComponent("secret.md")
        try "hidden".write(to: hiddenNote, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 0)
    }

    func testCustomExtensionsRespected() async throws {
        // Create storage with custom extensions including "org"
        let customStorage = FileStorageService(notesDirectory: tempDir, allowedExtensions: Set(["md", "org"]))

        let mdFile = tempDir.appendingPathComponent("note.md")
        try "md content".write(to: mdFile, atomically: true, encoding: .utf8)

        let orgFile = tempDir.appendingPathComponent("note.org")
        try "org content".write(to: orgFile, atomically: true, encoding: .utf8)

        let txtFile = tempDir.appendingPathComponent("note.txt")
        try "txt content".write(to: txtFile, atomically: true, encoding: .utf8)

        let notes = try await customStorage.readAllNotes()
        XCTAssertEqual(notes.count, 2)

        let titles = Set(notes.map(\.title))
        XCTAssertTrue(titles.contains("note")) // both md and org have same title
        let bodies = Set(notes.map(\.body))
        XCTAssertTrue(bodies.contains("md content"))
        XCTAssertTrue(bodies.contains("org content"))
        XCTAssertFalse(bodies.contains("txt content"))
    }

    func testNestedSubdirectories() async throws {
        let deep = tempDir.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        let deepNote = deep.appendingPathComponent("Deep.md")
        try "deep content".write(to: deepNote, atomically: true, encoding: .utf8)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].filename, "a/b/c/Deep")
    }

    // MARK: - NSFileCoordinatorAdapter (iOS coordinator seam)

    func testNSFileCoordinatorAdapter_writeReadDeleteRoundTrip() async throws {
        let coordinatedStorage = FileStorageService(
            notesDirectory: tempDir,
            coordinator: NSFileCoordinatorAdapter()
        )

        let note = Note(title: "Coordinated Note", body: "coordinated body", tags: ["a"])
        try await coordinatedStorage.writeNote(note)

        let url = await coordinatedStorage.fileURL(for: note)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let result = try await coordinatedStorage.readNote(at: url)
        XCTAssertEqual(result.parsed.body, "coordinated body")
        XCTAssertEqual(result.parsed.frontmatter?.tags, ["a"])

        try await coordinatedStorage.deleteNote(note)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testNSFileCoordinatorAdapter_readAllNotes_matchesPassthrough() async throws {
        let file1 = tempDir.appendingPathComponent("Note One.md")
        let file2 = tempDir.appendingPathComponent("Note Two.md")
        try "Body one".write(to: file1, atomically: true, encoding: .utf8)
        try "Body two".write(to: file2, atomically: true, encoding: .utf8)

        let coordinatedStorage = FileStorageService(
            notesDirectory: tempDir,
            coordinator: NSFileCoordinatorAdapter()
        )
        let notes = try await coordinatedStorage.readAllNotes()
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(Set(notes.map(\.title)), ["Note One", "Note Two"])
    }
}
