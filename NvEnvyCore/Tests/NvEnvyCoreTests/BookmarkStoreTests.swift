import XCTest
@testable import NvEnvyCore

final class BookmarkStoreTests: XCTestCase {

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "nvEnvyBookmarks")
    }

    func testAddBookmark() {
        let store = BookmarkStore()
        let bookmark = Bookmark(name: "Test", searchQuery: "swift")
        store.add(bookmark)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].name, "Test")
        XCTAssertEqual(store.bookmarks[0].searchQuery, "swift")
    }

    func testRemoveBookmark() {
        let store = BookmarkStore()
        let b1 = Bookmark(name: "One", searchQuery: "a")
        let b2 = Bookmark(name: "Two", searchQuery: "b")
        store.add(b1)
        store.add(b2)
        store.remove(id: b1.id)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].name, "Two")
    }

    func testRemoveAtIndex() {
        let store = BookmarkStore()
        store.add(Bookmark(name: "One", searchQuery: "a"))
        store.add(Bookmark(name: "Two", searchQuery: "b"))
        store.remove(at: 0)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks[0].name, "Two")
    }

    func testRenameBookmark() {
        let store = BookmarkStore()
        let bookmark = Bookmark(name: "Old", searchQuery: "q")
        store.add(bookmark)
        store.rename(id: bookmark.id, to: "New")
        XCTAssertEqual(store.bookmarks[0].name, "New")
    }

    func testBookmarkAtIndex() {
        let store = BookmarkStore()
        XCTAssertNil(store.bookmark(at: 0))
        store.add(Bookmark(name: "First", searchQuery: "x"))
        XCTAssertEqual(store.bookmark(at: 0)?.name, "First")
        XCTAssertNil(store.bookmark(at: 5))
    }

    func testPersistence() {
        let store1 = BookmarkStore()
        store1.add(Bookmark(name: "Persisted", searchQuery: "test"))

        let store2 = BookmarkStore()
        XCTAssertEqual(store2.bookmarks.count, 1)
        XCTAssertEqual(store2.bookmarks[0].name, "Persisted")
    }

    func testBookmarkWithNoteID() {
        let store = BookmarkStore()
        let noteID = UUID()
        let bookmark = Bookmark(name: "Note BM", searchQuery: "q", noteID: noteID)
        store.add(bookmark)
        XCTAssertEqual(store.bookmarks[0].noteID, noteID)
    }

    func testReorder() {
        let store = BookmarkStore()
        store.add(Bookmark(name: "A", searchQuery: "a"))
        store.add(Bookmark(name: "B", searchQuery: "b"))
        store.add(Bookmark(name: "C", searchQuery: "c"))
        store.reorder(from: 2, to: 0)
        XCTAssertEqual(store.bookmarks[0].name, "C")
        XCTAssertEqual(store.bookmarks[1].name, "A")
        XCTAssertEqual(store.bookmarks[2].name, "B")
    }
}
