import XCTest
@testable import NvEnvyCore

final class IntentParsingTests: XCTestCase {
    func testTagParsingFromCommaSeparated() {
        let input = "swift, programming, notes"
        let tags = input.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(tags, ["swift", "programming", "notes"])
    }

    func testTagParsingEmpty() {
        let input = ""
        let tags = input.isEmpty ? [String]() : input.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(tags, [])
    }

    func testTagParsingSingleTag() {
        let input = "todo"
        let tags = input.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(tags, ["todo"])
    }

    func testTagParsingWithExtraSpaces() {
        let input = "  tag1  ,  tag2  ,  tag3  "
        let tags = input.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(tags, ["tag1", "tag2", "tag3"])
    }

    func testNoteTitleSanitizationForIntent() {
        let title = "My Note: A/B Test"
        let filename = Note.sanitizedFilename(from: title)
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("/"))
    }
}
