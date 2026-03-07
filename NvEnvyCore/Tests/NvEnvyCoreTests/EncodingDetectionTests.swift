import XCTest
@testable import NvEnvyCore

final class EncodingDetectionTests: XCTestCase {
    func testUTF8Detection() {
        let text = "Hello, world! 🌍"
        let data = text.data(using: .utf8)!
        let (decoded, encoding) = FileStorageService.decodeWithFallback(data)
        XCTAssertEqual(decoded, text)
        XCTAssertEqual(encoding, .utf8)
    }

    func testUTF16Detection() {
        let text = "Hello, UTF-16!"
        let data = text.data(using: .utf16)!
        let (decoded, encoding) = FileStorageService.decodeWithFallback(data)
        XCTAssertEqual(decoded, text)
        XCTAssertEqual(encoding, .utf16)
    }

    func testNonUTF8FallbackDecodes() {
        // Data with invalid UTF-8 byte sequences should still decode via fallback
        let bytes: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xE9, 0x21] // "Hello" + é(Latin1) + "!"
        let data = Data(bytes)
        let (decoded, encoding) = FileStorageService.decodeWithFallback(data)
        XCTAssertNotNil(decoded, "Should decode via some fallback encoding")
        XCTAssertNotEqual(encoding, .utf8, "Should not be UTF-8 since bytes are invalid UTF-8")
    }

    func testRoundTripUTF8() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = FileStorageService(notesDirectory: tempDir)
        let note = Note(title: "UTF8Test", body: "Héllo wörld", filename: "UTF8Test")
        try await storage.writeNote(note)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.body, "Héllo wörld")
        XCTAssertEqual(notes.first?.fileEncoding, .utf8)
    }

    func testAllowedExtensions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write an .md and a .txt file
        try "# MD Note".write(to: tempDir.appendingPathComponent("note1.md"), atomically: true, encoding: .utf8)
        try "TXT Note".write(to: tempDir.appendingPathComponent("note2.txt"), atomically: true, encoding: .utf8)
        try "Ignored".write(to: tempDir.appendingPathComponent("note3.log"), atomically: true, encoding: .utf8)

        let storage = FileStorageService(notesDirectory: tempDir)
        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 2)
        let titles = Set(notes.map(\.title))
        XCTAssertTrue(titles.contains("note1"))
        XCTAssertTrue(titles.contains("note2"))
    }
}
