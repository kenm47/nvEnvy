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

    // MARK: - Helpers

    private func seedAllNotes(_ notes: [Note]) {
        vm.allNotes = notes
        vm.filteredNotes = notes
    }
}
