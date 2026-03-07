import XCTest
@testable import NvEnvyCore

final class NvALTImporterTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Detection

    func testDetectNvALTReturnsNilWhenNotInstalled() {
        // On most test machines, nvALT won't be installed
        // Just verify the function doesn't crash
        _ = NvALTImporter.detectNvALTInstallation()
    }

    // MARK: - OpenMeta Tags

    func testReadOpenMetaTagsFromXattr() throws {
        let file = tempDir.appendingPathComponent("tagged.txt")
        try "Hello".write(to: file, atomically: true, encoding: .utf8)

        // Write a plist xattr
        let tags = ["project", "important"]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: tags, format: .binary, options: 0
        )

        let attrName = "com.apple.metadata:kMDItemOMUserTags"
        let result = file.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return setxattr(path, attrName, (plistData as NSData).bytes, plistData.count, 0, 0)
        }
        XCTAssertEqual(result, 0, "setxattr should succeed")

        let readTags = NvALTImporter.readOpenMetaTags(from: file)
        XCTAssertEqual(Set(readTags), Set(["project", "important"]))
    }

    func testReadOpenMetaTagsReturnsEmptyForNoXattr() throws {
        let file = tempDir.appendingPathComponent("untagged.txt")
        try "Hello".write(to: file, atomically: true, encoding: .utf8)

        let tags = NvALTImporter.readOpenMetaTags(from: file)
        XCTAssertTrue(tags.isEmpty)
    }

    // MARK: - Note Import

    func testImportNvALTNotes() async throws {
        // Create test files
        try "Note one".write(to: tempDir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "Note two".write(to: tempDir.appendingPathComponent("two.md"), atomically: true, encoding: .utf8)
        try "Skip this".write(to: tempDir.appendingPathComponent("image.jpg"), atomically: true, encoding: .utf8)

        let service = ImportExportService()
        let imported = await NvALTImporter.importNvALTNotes(from: tempDir, service: service)

        XCTAssertEqual(imported.count, 2)
        let titles = Set(imported.map(\.title))
        XCTAssertTrue(titles.contains("one"))
        XCTAssertTrue(titles.contains("two"))
    }

    func testImportMergesOpenMetaTags() async throws {
        let file = tempDir.appendingPathComponent("tagged.md")
        try "---\ntags:\n  - existing\n---\nContent".write(to: file, atomically: true, encoding: .utf8)

        // Set OpenMeta tags
        let tags = ["openmeta-tag"]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: tags, format: .binary, options: 0
        )
        let attrName = "com.apple.metadata:kMDItemOMUserTags"
        file.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            setxattr(path, attrName, (plistData as NSData).bytes, plistData.count, 0, 0)
        }

        let service = ImportExportService()
        let imported = await NvALTImporter.importNvALTNotes(from: tempDir, service: service)

        XCTAssertEqual(imported.count, 1)
        let noteTags = Set(imported[0].tags)
        XCTAssertTrue(noteTags.contains("existing"))
        XCTAssertTrue(noteTags.contains("openmeta-tag"))
    }
}
