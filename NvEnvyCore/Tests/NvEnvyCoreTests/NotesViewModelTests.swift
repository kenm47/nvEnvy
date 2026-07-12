import XCTest
@testable import NvEnvyCore

@MainActor
final class NotesViewModelTests: XCTestCase {
    var vm: NotesViewModel!

    override func setUp() async throws {
        vm = NotesViewModel()
    }

    override func tearDown() async throws {
        vm = nil
    }

    // MARK: - createOrSelectNote() — exact-match path (synchronous, no store needed)

    func testCreateOrSelect_emptyQuery_isNoOp() {
        seedAllNotes([Note(title: "Existing")])
        vm.searchQuery = ""
        vm.createOrSelectNote()
        XCTAssertNil(vm.selectedNoteID)
    }

    func testCreateOrSelect_whitespaceOnlyQuery_isNoOp() {
        seedAllNotes([Note(title: "Existing")])
        vm.searchQuery = "   \n\t"
        vm.createOrSelectNote()
        XCTAssertNil(vm.selectedNoteID)
    }

    func testCreateOrSelect_exactMatch_selectsExistingNote() {
        let target = Note(title: "Meeting Notes")
        seedAllNotes([Note(title: "Other"), target])
        vm.searchQuery = "Meeting Notes"
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, target.id)
        XCTAssertEqual(vm.allNotes.count, 2, "must not create a duplicate")
    }

    func testCreateOrSelect_caseInsensitiveMatch_selectsExistingNote() {
        let target = Note(title: "Meeting Notes")
        seedAllNotes([target])
        vm.searchQuery = "meeting NOTES"
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, target.id)
        XCTAssertEqual(vm.allNotes.count, 1)
    }

    func testCreateOrSelect_trailingWhitespace_selectsExistingNote() {
        let target = Note(title: "Meeting Notes")
        seedAllNotes([target])
        vm.searchQuery = "  Meeting Notes  "
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, target.id, "trimmed query must match seeded title")
        XCTAssertEqual(vm.allNotes.count, 1)
    }

    func testCreateOrSelect_leadingNewlineAndCase_selectsExistingNote() {
        let target = Note(title: "Meeting Notes")
        seedAllNotes([target])
        vm.searchQuery = "\n  MEETING notes\t"
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, target.id)
    }

    func testCreateOrSelect_noMatchButNoStore_doesNotCrashAndDoesNotSelect() {
        // No noteStore attached: the no-match path enters the Task block
        // but the `guard let store = noteStore` short-circuits. The view model
        // must remain in a consistent state (no selection, no allNotes changes).
        seedAllNotes([Note(title: "Other")])
        vm.searchQuery = "Brand New"
        vm.createOrSelectNote()
        XCTAssertNil(vm.selectedNoteID)
        XCTAssertEqual(vm.allNotes.count, 1)
    }

    // MARK: - tryRenameNote()

    func testTryRename_emptyTitle_returnsError_andDoesNotMutate() {
        let note = Note(title: "Original")
        seedAllNotes([note])
        let err = vm.tryRenameNote(noteID: note.id, newTitle: "   ")
        XCTAssertNotNil(err)
        XCTAssertEqual(vm.allNotes.first?.title, "Original")
    }

    func testTryRename_collision_returnsError_andDoesNotMutate() {
        let foo = Note(title: "Foo")
        let bar = Note(title: "Bar")
        seedAllNotes([foo, bar])
        let err = vm.tryRenameNote(noteID: bar.id, newTitle: "Foo")
        XCTAssertNotNil(err)
        XCTAssertEqual(vm.allNotes.first(where: { $0.id == bar.id })?.title, "Bar")
        XCTAssertEqual(vm.allNotes.first(where: { $0.id == foo.id })?.title, "Foo")
    }

    func testTryRename_caseInsensitiveCollision_returnsError() {
        let foo = Note(title: "Foo")
        let bar = Note(title: "Bar")
        seedAllNotes([foo, bar])
        let err = vm.tryRenameNote(noteID: bar.id, newTitle: "FOO")
        XCTAssertNotNil(err)
    }

    func testTryRename_sameTitleAsCurrent_isNoOpSuccess() {
        let foo = Note(title: "Foo")
        seedAllNotes([foo])
        let err = vm.tryRenameNote(noteID: foo.id, newTitle: "Foo")
        XCTAssertNil(err)
    }

    // MARK: - deleteNote()

    func testDeleteNote_synchronouslyRemovesFromMemoryAndClearsSelection() {
        let foo = Note(title: "Foo")
        let bar = Note(title: "Bar")
        seedAllNotes([foo, bar])
        vm.selectedNoteID = foo.id

        vm.deleteNote(noteID: foo.id)

        // No awaiting: the in-memory removal must be observable on return.
        XCTAssertEqual(vm.allNotes.count, 1)
        XCTAssertEqual(vm.allNotes.first?.id, bar.id)
        XCTAssertNil(vm.selectedNoteID)
    }

    func testDeleteNote_otherSelection_remainsIntact() {
        let foo = Note(title: "Foo")
        let bar = Note(title: "Bar")
        seedAllNotes([foo, bar])
        vm.selectedNoteID = bar.id

        vm.deleteNote(noteID: foo.id)

        XCTAssertEqual(vm.allNotes.count, 1)
        XCTAssertEqual(vm.selectedNoteID, bar.id)
    }

    // MARK: - Debounced / off-main search

    func testSearch_isDebounced_thenAppliesFilteredResults() async throws {
        let apple = Note(title: "apple")
        let banana = Note(title: "banana")
        seedAllNotes([apple, banana])

        vm.searchQuery = "apple"
        // Synchronously after assigning the query the debounce has not fired,
        // so the list is still unfiltered.
        XCTAssertEqual(vm.filteredNotes.count, 2)

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(vm.filteredNotes.map(\.title), ["apple"])
    }

    func testSearch_rapidQueryChanges_settleOnFinalQuery() async throws {
        let alpha = Note(title: "alpha")
        let abacus = Note(title: "abacus")
        seedAllNotes([alpha, abacus])

        // Rapid changes: only the final query's results must remain.
        vm.searchQuery = "z"
        vm.searchQuery = "ab"
        vm.searchQuery = "alpha"

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(vm.filteredNotes.map(\.title), ["alpha"])
    }

    func testClearSearch_restoresAllNotes() async throws {
        let apple = Note(title: "apple")
        let banana = Note(title: "banana")
        seedAllNotes([apple, banana])

        vm.searchQuery = "apple"
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(vm.filteredNotes.count, 1)

        vm.clearSearch()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(vm.filteredNotes.count, 2)
    }

    // MARK: - showCreateRow

    func testShowCreateRow_emptyQuery_false() {
        seedAllNotes([Note(title: "Existing")])
        XCTAssertFalse(vm.showCreateRow)
    }

    func testShowCreateRow_novelQuery_true() async throws {
        seedAllNotes([Note(title: "Existing")])
        vm.searchQuery = "Brand New"
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(vm.showCreateRow)
    }

    func testShowCreateRow_exactMatch_false() async throws {
        seedAllNotes([Note(title: "Meeting Notes")])
        vm.searchQuery = "meeting notes"
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(vm.showCreateRow)
    }

    // MARK: - flushBeforeQuit() persists the pending debounced body edit

    func testFlushBeforeQuit_persistsPendingBodyEdit_evenBeforeDebounceFires() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NvEnvyCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        vm.attach(folderURL: tempDir)
        // Let the initial (empty) load complete.
        try await Task.sleep(for: .milliseconds(50))

        vm.searchQuery = "Quit Test"
        vm.createOrSelectNote()
        try await Task.sleep(for: .milliseconds(50))
        guard let note = vm.allNotes.first else {
            return XCTFail("note was not created")
        }

        // Update the body but do NOT wait for the 500ms debounce — this is
        // the state the app is in if it's backgrounded/killed right after a
        // keystroke. flushBeforeQuit must not lose this edit.
        vm.updateNoteBody(noteID: note.id, body: "unsaved edit")
        await vm.flushBeforeQuit()

        let fileURL = tempDir.appendingPathComponent(note.filename + ".md")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("unsaved edit"), "flushBeforeQuit must persist the pending debounced edit")
    }

    // MARK: - Helpers

    private func seedAllNotes(_ notes: [Note]) {
        vm.allNotes = notes
        vm.filteredNotes = notes
    }
}
