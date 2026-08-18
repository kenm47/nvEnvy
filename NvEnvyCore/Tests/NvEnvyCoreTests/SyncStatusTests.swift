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

    // MARK: - NotesViewModel.conflictedNotes precomputation (P5b)

    @MainActor
    func testConflictedNotesTracksSyncStatusMutations() {
        let vm = NotesViewModel()
        let a = Note(title: "A", filename: "A")
        let b = Note(title: "B", filename: "B")
        vm.allNotes = [a, b]
        XCTAssertEqual(vm.conflictedNotes, [])

        vm.updateSyncStatus(filename: "A", status: .conflict)
        XCTAssertEqual(vm.conflictedNotes, [a])

        vm.updateSyncStatuses(["B": .conflict])
        XCTAssertEqual(Set(vm.conflictedNotes), Set([a, b]))

        vm.updateSyncStatus(filename: "A", status: .current)
        XCTAssertEqual(vm.conflictedNotes, [b])
    }

    @MainActor
    func testConflictedNotesRebuiltWhenAllNotesReassigned() {
        let vm = NotesViewModel()
        let a = Note(title: "A", filename: "A")
        a.syncStatus = .conflict
        vm.allNotes = [a]
        XCTAssertEqual(vm.conflictedNotes, [a])

        // A fresh load (e.g. reconciliation) replaces `allNotes` wholesale --
        // the precomputed list must reflect the new snapshot, not the old one.
        vm.allNotes = []
        XCTAssertEqual(vm.conflictedNotes, [])
    }
}
