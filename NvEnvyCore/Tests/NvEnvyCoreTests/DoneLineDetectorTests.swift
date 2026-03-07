import XCTest
@testable import NvEnvyCore

final class DoneLineDetectorTests: XCTestCase {
    func testSingleDoneLine() {
        let text = "- Task 1 @done\n- Task 2"
        let ranges = DoneLineDetector.doneLineRanges(in: text)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(String(text[ranges[0]]), "- Task 1 @done")
    }

    func testMultipleDoneLines() {
        let text = "- Task 1 @done\n- Task 2\n- Task 3 @done"
        let ranges = DoneLineDetector.doneLineRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
    }

    func testNoDoneLines() {
        let text = "- Task 1\n- Task 2\n- Task 3"
        let ranges = DoneLineDetector.doneLineRanges(in: text)
        XCTAssertEqual(ranges.count, 0)
    }

    func testLineContainsDone() {
        XCTAssertTrue(DoneLineDetector.lineContainsDone("- Task @done"))
        XCTAssertTrue(DoneLineDetector.lineContainsDone("@done"))
        XCTAssertFalse(DoneLineDetector.lineContainsDone("- Task"))
        XCTAssertFalse(DoneLineDetector.lineContainsDone("done"))
    }

    func testDoneInMiddleOfLine() {
        let text = "Some text @done more text"
        let ranges = DoneLineDetector.doneLineRanges(in: text)
        XCTAssertEqual(ranges.count, 1)
    }

    func testEmptyText() {
        let ranges = DoneLineDetector.doneLineRanges(in: "")
        XCTAssertEqual(ranges.count, 0)
    }
}
