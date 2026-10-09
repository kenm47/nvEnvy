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

    func testCreateOrSelect_prefixMatch_selectsBestMatchAndCreatesNothing() {
        let shopping = Note(title: "Shopping List")
        let show = Note(title: "Show Notes")
        seedAllNotes([show, shopping])
        vm.searchQuery = "Sho"
        var committed: UUID?
        vm.onNoteCommitted = { committed = $0 }
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, show.id, "shortest title wins")
        XCTAssertEqual(committed, show.id)
        XCTAssertEqual(vm.allNotes.count, 2)
        XCTAssertEqual(vm.searchQuery, "Sho")
    }

    func testCreateOrSelect_exactMatchBeatsLongerPrefixMatch() {
        let shop = Note(title: "Shop")
        seedAllNotes([Note(title: "Shopping List"), shop])
        vm.searchQuery = "Shop"
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, shop.id)
    }

    func testCreateOrSelect_prefixMatch_isCaseInsensitiveAndTrimmed() {
        let target = Note(title: "Shopping List")
        seedAllNotes([target])
        vm.searchQuery = "  sho \n"
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, target.id)
        XCTAssertEqual(vm.allNotes.count, 1)
    }

    func testCreateOrSelect_allowPrefixMatchFalse_doesNotSelectPrefixMatch() {
        seedAllNotes([Note(title: "Shopping List")])
        vm.searchQuery = "Sho"
        vm.createOrSelectNote(allowPrefixMatch: false)
        // Falls through to the create path (no store attached here, so nothing lands).
        XCTAssertNil(vm.selectedNoteID)
    }

    func testCreateOrSelect_allowPrefixMatchFalse_stillSelectsExactMatch() {
        let target = Note(title: "Shop")
        seedAllNotes([target, Note(title: "Shopping List")])
        vm.searchQuery = "Shop"
        vm.createOrSelectNote(allowPrefixMatch: false)
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

        let fileURL = tempDir.appendingPathComponent(note.filename)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("unsaved edit"), "flushBeforeQuit must persist the pending debounced edit")
    }

    // MARK: - updateNoteBody() assigns modifiedDate synchronously (P4)

    func testUpdateNoteBody_assignsModifiedDateSynchronously_notDeferredToDebounce() {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let note = Note(title: "T", body: "old", modifiedDate: old)
        seedAllNotes([note])

        vm.updateNoteBody(noteID: note.id, body: "new")

        // Must be updated immediately -- if the user types and then
        // immediately switches notes or quits, the debounced task is
        // cancelled and would never run.
        XCTAssertGreaterThan(note.modifiedDate, old)
    }

    // MARK: - Helpers

    private func seedAllNotes(_ notes: [Note]) {
        vm.allNotes = notes
        vm.filteredNotes = notes
    }

    // MARK: - Live preview (autoSelectTitleMatch)

    private func search(_ query: String) async throws {
        vm.searchQuery = query
        try await Task.sleep(for: .milliseconds(300))
    }

    func testAutoSelect_prefixMatch_selectsWithoutCommitting() async throws {
        let shopping = Note(title: "Shopping List")
        seedAllNotes([shopping, Note(title: "Meeting")])
        vm.autoSelectTitleMatch = true
        var committed = false
        vm.onNoteCommitted = { _ in committed = true }
        let before = shopping.modifiedDate
        try await search("Sho")
        XCTAssertEqual(vm.selectedNoteID, shopping.id)
        XCTAssertFalse(committed)
        XCTAssertTrue(vm.snapbackStack.isEmpty)
        XCTAssertEqual(shopping.modifiedDate, before)
    }

    func testAutoSelect_exactMatch() async throws {
        let meeting = Note(title: "Meeting")
        seedAllNotes([Note(title: "Shopping List"), meeting])
        vm.autoSelectTitleMatch = true
        try await search("Meeting")
        XCTAssertEqual(vm.selectedNoteID, meeting.id)
    }

    func testAutoSelect_prefersBestPrefixAndAgreesWithReturn() async throws {
        let shop = Note(title: "Shop")
        seedAllNotes([Note(title: "Shopping List"), shop])
        vm.autoSelectTitleMatch = true
        try await search("Sho")
        XCTAssertEqual(vm.selectedNoteID, shop.id)
        vm.selectedNoteID = nil
        vm.createOrSelectNote()
        XCTAssertEqual(vm.selectedNoteID, shop.id)
    }

    func testAutoSelect_substringOrBodyTopResult_doesNotSelect() async throws {
        seedAllNotes([Note(title: "Grocery Shopping"), Note(title: "Other", body: "shop")])
        vm.autoSelectTitleMatch = true
        try await search("shop")
        XCTAssertNil(vm.selectedNoteID)
    }

    func testAutoSelect_disabled_doesNotSelect() async throws {
        seedAllNotes([Note(title: "Shopping List")])
        vm.autoSelectTitleMatch = false
        try await search("Sho")
        XCTAssertNil(vm.selectedNoteID)
    }

    func testAutoSelect_emptyQuery_clearsAutoSelectionAndSelectsNothing() async throws {
        seedAllNotes([Note(title: "Shopping List"), Note(title: "Meeting")])
        vm.autoSelectTitleMatch = true
        try await search("Sho")
        XCTAssertNotNil(vm.selectedNoteID)
        try await search("")
        XCTAssertNil(vm.selectedNoteID)
    }

    func testAutoSelect_followsNarrowingQuery() async throws {
        let shopping = Note(title: "Shopping List")
        let show = Note(title: "Show Notes")
        seedAllNotes([shopping, show])
        vm.autoSelectTitleMatch = true
        try await search("Sho")
        try await search("Shopp")
        XCTAssertEqual(vm.selectedNoteID, shopping.id)
        try await search("Show")
        XCTAssertEqual(vm.selectedNoteID, show.id)
    }

    func testAutoSelect_staleAutoSelection_clearsWhenNothingMatches() async throws {
        seedAllNotes([Note(title: "Shopping List")])
        vm.autoSelectTitleMatch = true
        try await search("Sho")
        try await search("Shx")
        XCTAssertNil(vm.selectedNoteID)
        XCTAssertNil(vm.autoSelectedNoteID)
    }

    func testAutoSelect_userSelectionWinsAndResumesAfterClear() async throws {
        let a = Note(title: "Shopping List")
        let b = Note(title: "Other")
        seedAllNotes([a, b])
        vm.autoSelectTitleMatch = true
        try await search("Sho")
        XCTAssertEqual(vm.selectedNoteID, a.id)
        vm.selectedNoteID = b.id
        try await search("Shop")
        XCTAssertEqual(vm.selectedNoteID, b.id)
        try await search("Zzz")
        XCTAssertEqual(vm.selectedNoteID, b.id, "a hand-picked note is never cleared")

        vm.selectedNoteID = nil
        vm.clearSearch()
        try await Task.sleep(for: .milliseconds(100))
        try await search("Sho")
        XCTAssertEqual(vm.selectedNoteID, a.id)
    }

    func testAutoSelect_tagFilterGate() async throws {
        seedAllNotes([Note(title: "Shopping List", tags: ["work"])])
        vm.autoSelectTitleMatch = true
        vm.tagFilter = "work"
        try await search("Sho")
        XCTAssertNil(vm.selectedNoteID)
    }

    func testAutoSelect_staleResultDropped() async throws {
        seedAllNotes([Note(title: "Shopping List")])
        vm.autoSelectTitleMatch = true
        vm.searchQuery = "Sho"
        vm.searchQuery = "Zzz"
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(vm.selectedNoteID)
    }

    func testAutoSelect_returnCommitsAndLaterNoMatchKeepsSelection() async throws {
        let shopping = Note(title: "Shopping List")
        seedAllNotes([shopping])
        vm.autoSelectTitleMatch = true
        var committed: UUID?
        vm.onNoteCommitted = { committed = $0 }
        try await search("Sho")
        vm.createOrSelectNote()
        XCTAssertEqual(committed, shopping.id)
        XCTAssertEqual(vm.allNotes.count, 1)
        XCTAssertNil(vm.autoSelectedNoteID)
        try await search("Zzz")
        XCTAssertEqual(vm.selectedNoteID, shopping.id)
    }

    // MARK: - rebuildNotesByID() — duplicate-filename launch crash

    func testDuplicateFilenamesDoNotTrap() {
        // Regression: a vault containing e.g. `Ideas.md` and `Ideas.txt` used
        // to collide on the same key and trap `Dictionary(uniqueKeysWithValues:)`
        // on launch. `filename` here is the same key `NoteStore` would derive
        // for two on-disk files sharing a stem.
        let a = Note(title: "Ideas", filename: "Ideas.md")
        let b = Note(title: "Ideas", filename: "Ideas.txt")
        seedAllNotes([a, b]) // must not crash
        XCTAssertEqual(vm.allNotes.count, 2)
        XCTAssertNotNil(vm.note(for: a.id))
        XCTAssertNotNil(vm.note(for: b.id))
    }

    func testSyncStatusMatchesNoteInSubfolder() {
        // Regression: sync-status keys used to be `lastPathComponent` with the
        // extension stripped, which drops the directory entirely — a note at
        // "Daily/log.md" was keyed as "log" and never matched.
        let note = Note(title: "log", filename: "Daily/log.md")
        seedAllNotes([note])
        vm.updateSyncStatus(filename: "Daily/log.md", status: .conflict)
        XCTAssertEqual(note.syncStatus, .conflict)
    }
}
