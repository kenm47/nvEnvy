import XCTest
@testable import NvEnvyCore

final class FinderTagServiceTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testWriteAndReadFinderTags() throws {
        let fileURL = tempDir.appendingPathComponent("test.md")
        try "# Test".write(to: fileURL, atomically: true, encoding: .utf8)

        let tags = ["swift", "programming"]
        FinderTagService.writeFinderTags(tags, to: fileURL)

        let readTags = FinderTagService.readFinderTags(from: fileURL)
        XCTAssertEqual(readTags, tags)
    }

    func testReadFinderTagsEmpty() throws {
        let fileURL = tempDir.appendingPathComponent("empty.md")
        try "Hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let tags = FinderTagService.readFinderTags(from: fileURL)
        XCTAssertTrue(tags.isEmpty)
    }

    func testMigrateFinderTagsWhenNoFrontmatterTags() throws {
        let fileURL = tempDir.appendingPathComponent("migrate.md")
        try "Body text".write(to: fileURL, atomically: true, encoding: .utf8)

        // Set Finder tags on the file
        FinderTagService.writeFinderTags(["imported", "todo"], to: fileURL)

        let note = Note(title: "Migrate", body: "Body text", tags: [], filename: "migrate")
        let migrated = FinderTagService.migrateFinderTagsIfNeeded(for: note, fileURL: fileURL)
        XCTAssertTrue(migrated)
        XCTAssertEqual(note.tags, ["imported", "todo"])
    }

    func testNoMigrationWhenNoteHasTags() throws {
        let fileURL = tempDir.appendingPathComponent("existing.md")
        try "Body".write(to: fileURL, atomically: true, encoding: .utf8)

        FinderTagService.writeFinderTags(["finder-tag"], to: fileURL)

        let note = Note(title: "Existing", body: "Body", tags: ["existing-tag"], filename: "existing")
        let migrated = FinderTagService.migrateFinderTagsIfNeeded(for: note, fileURL: fileURL)
        XCTAssertFalse(migrated)
        XCTAssertEqual(note.tags, ["existing-tag"])
    }
}
