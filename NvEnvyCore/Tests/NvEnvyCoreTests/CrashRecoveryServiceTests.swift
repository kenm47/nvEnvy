import XCTest
@testable import NvEnvyCore

final class CrashRecoveryServiceTests: XCTestCase {
    var tempDir: URL!
    var service: CrashRecoveryService!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = CrashRecoveryService(cacheDirectory: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAppendAndRecover() async throws {
        let note = Note(title: "Test Note", body: "Hello world", tags: ["tag1", "tag2"])
        try await service.appendRecord(note: note)

        let recovered = try await service.recoverPendingNotes()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].noteID, note.id)
        XCTAssertEqual(recovered[0].title, "Test Note")
        XCTAssertEqual(recovered[0].body, "Hello world")
        XCTAssertEqual(recovered[0].tags, ["tag1", "tag2"])
    }

    func testMultipleRecords() async throws {
        let note1 = Note(title: "Note 1", body: "Body 1")
        let note2 = Note(title: "Note 2", body: "Body 2")
        try await service.appendRecord(note: note1)
        try await service.appendRecord(note: note2)

        let recovered = try await service.recoverPendingNotes()
        XCTAssertEqual(recovered.count, 2)
        let titles = Set(recovered.map(\.title))
        XCTAssertTrue(titles.contains("Note 1"))
        XCTAssertTrue(titles.contains("Note 2"))
    }

    func testDeduplicationByNoteID() async throws {
        let note = Note(title: "Original", body: "v1")

        try await service.appendRecord(note: note)

        // Simulate edit
        note.body = "v2"
        note.title = "Updated"
        try await service.appendRecord(note: note)

        let recovered = try await service.recoverPendingNotes()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].noteID, note.id)
        XCTAssertEqual(recovered[0].title, "Updated")
        XCTAssertEqual(recovered[0].body, "v2")
    }

    func testTruncate() async throws {
        let note = Note(title: "Test", body: "body")
        try await service.appendRecord(note: note)

        try await service.truncate()

        let recovered = try await service.recoverPendingNotes()
        XCTAssertEqual(recovered.count, 0)
    }

    func testRecoverEmptyWAL() async throws {
        let recovered = try await service.recoverPendingNotes()
        XCTAssertEqual(recovered.count, 0)
    }

    func testCRCValidation() async throws {
        let note = Note(title: "CRC Test", body: "data")
        try await service.appendRecord(note: note)

        // Corrupt the WAL file
        let walURL = tempDir.appendingPathComponent("wal.bin")
        var data = try Data(contentsOf: walURL)
        // Corrupt a byte in the compressed payload (after 12-byte header)
        if data.count > 14 {
            data[14] ^= 0xFF
        }
        try data.write(to: walURL)

        let recovered = try await service.recoverPendingNotes()
        XCTAssertEqual(recovered.count, 0, "Corrupted record should be skipped")
    }

    func testCompressionRoundTrip() throws {
        let original = "Hello, world! This is a test of compression.".data(using: .utf8)!
        let compressed = try CrashRecoveryService.compress(original)
        let decompressed = try CrashRecoveryService.decompress(compressed, originalSize: original.count)
        XCTAssertEqual(decompressed, original)
    }

    func testCRC32Checksum() {
        let data = "test data".data(using: .utf8)!
        let crc1 = CrashRecoveryService.crc32Checksum(data)
        let crc2 = CrashRecoveryService.crc32Checksum(data)
        XCTAssertEqual(crc1, crc2)

        let different = "other data".data(using: .utf8)!
        let crc3 = CrashRecoveryService.crc32Checksum(different)
        XCTAssertNotEqual(crc1, crc3)
    }
}
