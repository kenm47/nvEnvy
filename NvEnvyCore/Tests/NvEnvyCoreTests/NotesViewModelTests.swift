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

    // MARK: - Helpers

    private func seedAllNotes(_ notes: [Note]) {
        vm.allNotes = notes
        vm.filteredNotes = notes
    }
}
