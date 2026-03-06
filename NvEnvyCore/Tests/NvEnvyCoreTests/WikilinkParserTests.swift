import XCTest
@testable import NvEnvyCore

final class WikilinkParserTests: XCTestCase {

    func testFindSingleWikilink() {
        let text = "Check out [[My Note]] for more."
        let results = WikilinkParser.findWikilinks(in: text)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "My Note")
    }

    func testFindMultipleWikilinks() {
        let text = "See [[Note A]] and also [[Note B]]."
        let results = WikilinkParser.findWikilinks(in: text)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Note A")
        XCTAssertEqual(results[1].title, "Note B")
    }

    func testNoWikilinks() {
        let text = "Plain text without any links."
        let results = WikilinkParser.findWikilinks(in: text)
        XCTAssertTrue(results.isEmpty)
    }

    func testEmptyWikilink() {
        let text = "Empty [[]] link."
        let results = WikilinkParser.findWikilinks(in: text)
        // The regex requires at least one character between brackets
        XCTAssertTrue(results.isEmpty)
    }

    func testWikilinkWithSpecialCharacters() {
        let text = "Link to [[Note with spaces & symbols!]]"
        let results = WikilinkParser.findWikilinks(in: text)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Note with spaces & symbols!")
    }

    func testNSRanges() {
        let text = "Hello [[World]] end"
        let results = WikilinkParser.findWikilinkNSRanges(in: text)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "World")
        XCTAssertEqual(results[0].range.location, 6)
        XCTAssertEqual(results[0].range.length, 9) // [[World]]
    }

    func testNestedBracketsIgnored() {
        let text = "Text [[valid link]] and [not a link]"
        let results = WikilinkParser.findWikilinks(in: text)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "valid link")
    }
}
