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

    func testTitleMatchRanksAboveBodyOnlyMatch() {
        let notes = [
            Note(title: "Note A", body: "Mentions swift only in the body"),
            Note(title: "Swift Note B"),
        ]
        let results = engine.filter(notes: notes, query: "swift")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Swift Note B")
        XCTAssertEqual(results[1].title, "Note A")
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
        let match = SearchEngine.exactTitleMatch(notes: notes, query: "test note")
        XCTAssertEqual(match?.title, "Test Note")
    }

    func testMixedQuotedUnquotedTokens() {
        let notes = [
            Note(title: "Note A", body: "hello world swift programming"),
            Note(title: "Note B", body: "hello world python guide"),
            Note(title: "Note C", body: "hello test world swift"),
        ]
        let results = engine.filter(notes: notes, query: "\"hello world\" swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Note A")
    }

    func testBestTitlePrefixMatch_prefersShortestTitle() {
        let notes = [
            Note(title: "Apple Pie Recipe"),
            Note(title: "Banana Split"),
            Note(title: "Apple Pie"),
        ]
        let match = SearchEngine.bestTitlePrefixMatch(notes: notes, query: "app")
        XCTAssertEqual(match?.title, "Apple Pie")
    }

    func testBestTitlePrefixMatch_tieBreaksByModifiedDateThenAlphabetical() {
        let old = Date(timeIntervalSince1970: 1000)
        let new = Date(timeIntervalSince1970: 2000)
        let a = Note(title: "Shop B", modifiedDate: old)
        let b = Note(title: "Shop A", modifiedDate: new)
        XCTAssertEqual(SearchEngine.bestTitlePrefixMatch(notes: [a, b], query: "sho")?.title, "Shop A")
        XCTAssertEqual(SearchEngine.bestTitlePrefixMatch(notes: [b, a], query: "sho")?.title, "Shop A")

        let c = Note(title: "Shop B", modifiedDate: new)
        XCTAssertEqual(SearchEngine.bestTitlePrefixMatch(notes: [c, b], query: "sho")?.title, "Shop A")
        XCTAssertEqual(SearchEngine.bestTitlePrefixMatch(notes: [b, c], query: "sho")?.title, "Shop A")
    }

    func testBestTitlePrefixMatch_isCaseInsensitive() {
        let notes = [Note(title: "Shopping List")]
        XCTAssertNotNil(SearchEngine.bestTitlePrefixMatch(notes: notes, query: "SHO"))
    }

    func testBestTitlePrefixMatchNoMatch() {
        let notes = [Note(title: "Banana Split")]
        XCTAssertNil(SearchEngine.bestTitlePrefixMatch(notes: notes, query: "app"))
    }

    func testBestTitlePrefixMatchEmpty() {
        let notes = [Note(title: "Test")]
        XCTAssertNil(SearchEngine.bestTitlePrefixMatch(notes: notes, query: ""))
    }

    func testRanking_prefixThenSubstringThenBody() {
        let body = Note(title: "Zeta", body: "mentions shop here")
        let substring = Note(title: "Grocery Shopping")
        let prefix = Note(title: "Shopping List")
        let exact = Note(title: "Shop")
        let results = engine.filter(notes: [body, substring, prefix, exact], query: "shop")
        XCTAssertEqual(results.map(\.title), ["Shop", "Shopping List", "Grocery Shopping", "Zeta"])
    }

    func testRanking_incrementalMatchesColdSearch() {
        let notes = [
            Note(title: "Grocery Shopping"),
            Note(title: "Shopping List"),
            Note(title: "Shop"),
            Note(title: "Other", body: "shop"),
        ]
        _ = engine.filter(notes: notes, query: "s")
        _ = engine.filter(notes: notes, query: "sh")
        _ = engine.filter(notes: notes, query: "s")
        let retyped = engine.filter(notes: notes, query: "sho")
        var cold = SearchEngine()
        XCTAssertEqual(retyped.map(\.id), cold.filter(notes: notes, query: "sho").map(\.id))
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
