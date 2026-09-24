import XCTest
@testable import NvEnvyCore

final class BookmarkStoreTests: XCTestCase {
    // Each test gets its own UserDefaults suite so `swift test --parallel`
    // (which runs suites in separate processes sharing the app's
    // UserDefaults domain) can't have one test's writes clobber another's.
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "nvEnvyBookmarkStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> BookmarkStore {
        BookmarkStore(defaults: defaults)
    }

    func testAddBookmark() {
        let store = makeStore()
        let bookmark = Bookmark(name: "Test", searchQuery: "swift")
        store.add(bookmark)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].name, "Test")
        XCTAssertEqual(store.bookmarks[0].searchQuery, "swift")
    }

    func testRemoveBookmark() {
        let store = makeStore()
        let b1 = Bookmark(name: "One", searchQuery: "a")
        let b2 = Bookmark(name: "Two", searchQuery: "b")
        store.add(b1)
        store.add(b2)
        store.remove(id: b1.id)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].name, "Two")
    }

    func testRemoveAtIndex() {
        let store = makeStore()
        store.add(Bookmark(name: "One", searchQuery: "a"))
        store.add(Bookmark(name: "Two", searchQuery: "b"))
        store.remove(at: 0)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].name, "Two")
    }

    func testRenameBookmark() {
        let store = makeStore()
        let bookmark = Bookmark(name: "Old", searchQuery: "q")
        store.add(bookmark)
        store.rename(id: bookmark.id, to: "New")
        XCTAssertEqual(store.bookmarks[0].name, "New")
    }

    func testBookmarkAtIndex() {
        let store = makeStore()
        XCTAssertNil(store.bookmark(at: 0))
        store.add(Bookmark(name: "First", searchQuery: "x"))
        XCTAssertEqual(store.bookmark(at: 0)?.name, "First")
        XCTAssertNil(store.bookmark(at: 5))
    }

    func testPersistence() {
        let store1 = makeStore()
        store1.add(Bookmark(name: "Persisted", searchQuery: "test"))

        let store2 = makeStore()
        XCTAssertEqual(store2.bookmarks.count, 1)
        XCTAssertEqual(store2.bookmarks[0].name, "Persisted")
    }

    func testBookmarkWithNoteID() {
        let store = makeStore()
        let noteID = UUID()
        let bookmark = Bookmark(name: "Note BM", searchQuery: "q", noteID: noteID)
        store.add(bookmark)
        XCTAssertEqual(store.bookmarks[0].noteID, noteID)
    }

    func testReorder() {
        let store = makeStore()
        store.add(Bookmark(name: "A", searchQuery: "a"))
        store.add(Bookmark(name: "B", searchQuery: "b"))
        store.add(Bookmark(name: "C", searchQuery: "c"))
        store.reorder(from: 2, to: 0)
        XCTAssertEqual(store.bookmarks[0].name, "C")
        XCTAssertEqual(store.bookmarks[1].name, "A")
        XCTAssertEqual(store.bookmarks[2].name, "B")
    }
}
