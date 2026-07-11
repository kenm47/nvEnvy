import XCTest
@testable import NvEnvyCore

/// `Note.cachedFirstLine` lets preview rows show the first body line without
/// splitting the whole body on every render. It must stay correct across init
/// and `invalidateSearchCache()` (called whenever the body changes).
final class NoteCacheTests: XCTestCase {
    func testCachedFirstLine_simpleBody() {
        let note = Note(title: "T", body: "First line\nSecond line")
        XCTAssertEqual(note.cachedFirstLine, "First line")
    }

    func testCachedFirstLine_trimsLeadingBlankLinesAndWhitespace() {
        let note = Note(title: "T", body: "\n\n   Hello\nWorld")
        XCTAssertEqual(note.cachedFirstLine, "Hello")
    }

    func testCachedFirstLine_singleLineNoNewline() {
        let note = Note(title: "T", body: "Only one line")
        XCTAssertEqual(note.cachedFirstLine, "Only one line")
    }

    func testCachedFirstLine_emptyBody() {
        let note = Note(title: "T", body: "")
        XCTAssertEqual(note.cachedFirstLine, "")
    }

    func testCachedFirstLine_crlfBody() {
        let note = Note(title: "T", body: "Line one\r\nLine two")
        XCTAssertEqual(note.cachedFirstLine, "Line one")
    }

    func testCachedFirstLine_invalidatedAfterBodyChange() {
        let note = Note(title: "T", body: "old content")
        note.body = "new first line\nrest of body"
        note.invalidateSearchCache()
        XCTAssertEqual(note.cachedFirstLine, "new first line")
    }

    func testFirstLineMatchesLegacyComputation() {
        // The old implementation: trim then components(separatedBy: .newlines).first
        let bodies = ["a\nb", "  x  \ny", "\n\nfirst\n", "single", ""]
        for body in bodies {
            let legacy = body.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            XCTAssertEqual(Note.firstLine(of: body), legacy, "mismatch for body \(body.debugDescription)")
        }
    }
}
