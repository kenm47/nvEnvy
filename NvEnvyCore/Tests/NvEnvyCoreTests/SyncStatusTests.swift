import XCTest
@testable import NvEnvyCore

final class SyncStatusTests: XCTestCase {
    func testDefaultSyncStatusIsLocal() {
        let note = Note(title: "Test")
        XCTAssertEqual(note.syncStatus, .local)
    }

    func testSyncStatusValues() {
        XCTAssertEqual(SyncStatus.local.rawValue, 0)
        XCTAssertEqual(SyncStatus.uploading.rawValue, 1)
        XCTAssertEqual(SyncStatus.downloading.rawValue, 2)
        XCTAssertEqual(SyncStatus.current.rawValue, 3)
        XCTAssertEqual(SyncStatus.conflict.rawValue, 4)
    }

    func testSyncStatusAssignment() {
        let note = Note(title: "Test")
        note.syncStatus = .uploading
        XCTAssertEqual(note.syncStatus, .uploading)
        note.syncStatus = .conflict
        XCTAssertEqual(note.syncStatus, .conflict)
        note.syncStatus = .current
        XCTAssertEqual(note.syncStatus, .current)
    }

    func testNoteStoreUpdateSyncStatus() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = FileStorageService(notesDirectory: tempDir)
        let store = NoteStore(storage: storage)

        let note = try await store.createNote(title: "SyncTest")
        await store.updateSyncStatus(filename: note.filename, status: .uploading)

        let fetched = await store.note(for: note.id)
        XCTAssertEqual(fetched?.syncStatus, .uploading)
    }
}
