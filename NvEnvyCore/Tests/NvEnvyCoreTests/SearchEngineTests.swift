import XCTest
@testable import NvEnvyCore

final class SearchEngineTests: XCTestCase {
    var engine = SearchEngine()

    override func setUp() {
        engine = SearchEngine()
    }

    private func makeNotes(count: Int) -> [Note] {
        (0..<count).map { i in
            Note(title: "Note \(i)", body: "Body content for note number \(i). Some extra text here.")
        }
    }

    func testEmptyQueryReturnsAll() {
        let notes = makeNotes(count: 10)
        let results = engine.filter(notes: notes, query: "")
        XCTAssertEqual(results.count, 10)
    }

    func testBasicTitleMatch() {
        let notes = [
            Note(title: "Swift Programming"),
            Note(title: "Python Guide"),
            Note(title: "Rust Basics"),
        ]
        let results = engine.filter(notes: notes, query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Swift Programming")
    }

    func testBodyMatch() {
        let notes = [
            Note(title: "Note A", body: "Contains the word swift inside"),
            Note(title: "Note B", body: "No match here"),
        ]
        let results = engine.filter(notes: notes, query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Note A")
    }

    func testTagMatch() {
        let notes = [
            Note(title: "Note A", tags: ["swift", "ios"]),
            Note(title: "Note B", tags: ["python"]),
        ]
        let results = engine.filter(notes: notes, query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Note A")
    }

    func testMultiTokenSearch() {
        let notes = [
            Note(title: "Swift Programming", body: "A guide to Swift on macOS"),
            Note(title: "Swift Basics"),
            Note(title: "Python Programming"),
        ]
        let results = engine.filter(notes: notes, query: "swift programming")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Swift Programming")
    }

    func testPhraseSearch() {
        let notes = [
            Note(title: "Note A", body: "hello world test"),
            Note(title: "Note B", body: "hello test world"),
        ]
        let results = engine.filter(notes: notes, query: "\"hello world\"")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Note A")
    }

    func testCaseInsensitive() {
        let notes = [Note(title: "UPPERCASE Title")]
        let results = engine.filter(notes: notes, query: "uppercase")
        XCTAssertEqual(results.count, 1)
    }

    func testIncrementalFiltering() {
        let notes = makeNotes(count: 100)
        var results = engine.filter(notes: notes, query: "note 1")
        let firstCount = results.count
        // Extending query should filter from subset
        results = engine.filter(notes: notes, query: "note 10")
        XCTAssertLessThanOrEqual(results.count, firstCount)
    }

    func testExactTitleMatch() {
        let notes = [
            Note(title: "Test Note"),
            Note(title: "Test Note Extra"),
        ]
        let match = engine.exactTitleMatch(notes: notes, query: "test note")
        XCTAssertEqual(match?.title, "Test Note")
    }

    func testPerformanceAt1KNotes() {
        let notes = (0..<1000).map { i in
            Note(
                title: "Note \(i) - \(["swift", "python", "rust", "go", "java"].randomElement()!)",
                body: "This is the body content for note number \(i). It contains various words for searching.",
                tags: [["tag1", "tag2", "tag3"].randomElement()!]
            )
        }

        measure {
            var eng = SearchEngine()
            _ = eng.filter(notes: notes, query: "swift")
            _ = eng.filter(notes: notes, query: "swift note")
            _ = eng.filter(notes: notes, query: "body content")
        }
    }
}
