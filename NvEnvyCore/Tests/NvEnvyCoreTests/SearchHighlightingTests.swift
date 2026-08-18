import XCTest
@testable import NvEnvyCore

final class SearchHighlightingTests: XCTestCase {

    /// Reproduces the pre-fix algorithm (lowercase the whole document into a
    /// copy, search the copy, apply ranges from the copy to the original) to
    /// prove the bug it replaces was real.
    private func oldBuggyMatchRanges(in text: NSString, query: String) -> [NSRange] {
        let lowercaseQuery = query.lowercased()
        let nsText = (text as String).lowercased() as NSString

        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: lowercaseQuery, options: [], range: searchRange)
            guard foundRange.location != NSNotFound else { break }
            ranges.append(foundRange)
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }
        return ranges
    }

    /// `İ` (U+0130) lowercases to two UTF-16 code units (`i` + U+0307
    /// COMBINING DOT ABOVE), so a lowercased copy of the document is longer
    /// than the original whenever it contains one. That desyncs every
    /// subsequently computed range from the original text.
    func testOldAlgorithmMisplacesRangeAfterExpandingLowercase() {
        let text = "İstanbul is nice. istanbul again." as NSString
        let query = "istanbul"

        let buggyRanges = oldBuggyMatchRanges(in: text, query: query)

        // The combining dot above breaks the literal "istanbul" substring
        // match at the very start of the string, so the old algorithm only
        // finds the second, already-lowercase occurrence -- at a location
        // computed against the (longer) lowercased copy and then applied,
        // unshifted, to the original string.
        XCTAssertEqual(buggyRanges.count, 1)

        // Applying the buggy (copy-relative) range directly to the original
        // NSString does not land on "istanbul" -- proof the range is wrong.
        XCTAssertNotEqual(text.substring(with: buggyRanges[0]), "istanbul")
    }

    func testMatchRangesHandlesExpandingLowercaseCorrectly() {
        let text = "İstanbul is nice. istanbul again." as NSString
        let query = "istanbul"

        let ranges = SearchHighlighting.matchRanges(in: text, query: query)

        // Searching the original string directly means the range for the
        // (only) literal "istanbul" match is computed and applied against
        // the same string -- correct by construction, unlike the buggy
        // lowercase-copy approach above, which puts it at the wrong offset.
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(text.substring(with: ranges[0]), "istanbul")
    }

    func testMatchRangesEmptyQueryReturnsNoRanges() {
        let text = "Some text" as NSString
        XCTAssertEqual(SearchHighlighting.matchRanges(in: text, query: ""), [])
    }

    func testMatchRangesCaseInsensitive() {
        let text = "Hello World hello world HELLO" as NSString
        let ranges = SearchHighlighting.matchRanges(in: text, query: "hello")
        XCTAssertEqual(ranges.count, 3)
        for range in ranges {
            XCTAssertEqual(text.substring(with: range).lowercased(), "hello")
        }
    }

    func testMatchRangesNoDiacriticInsensitiveMatching() {
        // Do not match "café" when searching for "cafe" -- .diacriticInsensitive
        // must not be added, or the search would surface unrelated text.
        let text = "café au lait" as NSString
        XCTAssertEqual(SearchHighlighting.matchRanges(in: text, query: "cafe"), [])
    }
}
