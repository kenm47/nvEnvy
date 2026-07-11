import XCTest
@testable import NvEnvyCore

/// `SearchActor` runs `SearchEngine.filter` off the main actor. These tests
/// assert it produces identical results to the synchronous engine, including
/// the incremental-search fast path that depends on per-call state.
final class SearchActorTests: XCTestCase {
    private func fixtures() -> [Note] {
        [
            Note(title: "Swift Programming", body: "A guide to swift", tags: ["dev"]),
            Note(title: "Python Guide", body: "hello world python", tags: ["dev", "scripting"]),
            Note(title: "Rust Basics", body: "systems programming", tags: ["dev"]),
            Note(title: "Note A", body: "hello world swift programming", tags: ["misc"]),
            Note(title: "Note B", body: "no relevant content", tags: []),
        ]
    }

    func testParityWithSearchEngineForIndependentQueries() async {
        let notes = fixtures()
        let queries = ["swift", "swift programming", "\"hello world\"", "dev", "missing", ""]
        for query in queries {
            // Fresh engines so each query is independent (no incremental carry-over).
            var engine = SearchEngine()
            let actor = SearchActor()
            let expected = engine.filter(notes: notes, query: query)
            let actual = await actor.filter(notes: notes, query: query)
            XCTAssertEqual(actual.map(\.id), expected.map(\.id), "mismatch for query \"\(query)\"")
        }
    }

    func testIncrementalSequenceMatchesEngine() async {
        let notes = fixtures()
        // Extending queries exercise the incremental (prefix-of-previous) path.
        let sequence = ["s", "sw", "swift", "swift p", "swift prog"]
        var engine = SearchEngine()
        let actor = SearchActor()
        for query in sequence {
            let expected = engine.filter(notes: notes, query: query)
            let actual = await actor.filter(notes: notes, query: query)
            XCTAssertEqual(actual.map(\.id), expected.map(\.id), "mismatch for query \"\(query)\"")
        }
    }

    func testPhraseSearchParity() async {
        let notes = fixtures()
        var engine = SearchEngine()
        let actor = SearchActor()
        let expected = engine.filter(notes: notes, query: "\"hello world\" swift")
        let actual = await actor.filter(notes: notes, query: "\"hello world\" swift")
        XCTAssertEqual(actual.map(\.id), expected.map(\.id))
        XCTAssertEqual(actual.count, 1)
    }
}
