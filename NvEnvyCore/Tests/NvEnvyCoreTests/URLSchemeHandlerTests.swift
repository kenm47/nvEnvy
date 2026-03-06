import XCTest
@testable import NvEnvyCore

final class URLSchemeHandlerTests: XCTestCase {

    func testFindBySearchTerm() {
        let url = URL(string: "nvenvy://find/My%20Note")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNotNil(action)

        if case .find(let term, let id) = action!.kind {
            XCTAssertEqual(term, "My Note")
            XCTAssertNil(id)
        } else {
            XCTFail("Expected find action")
        }
    }

    func testFindByUUID() {
        let uuid = UUID()
        let base64 = uuid.uuidString.data(using: .utf8)!.base64EncodedString()
        let url = URL(string: "nvenvy://find/search?id=\(base64)")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNotNil(action)

        if case .find(let term, let id) = action!.kind {
            XCTAssertEqual(term, "search")
            XCTAssertEqual(id, uuid)
        } else {
            XCTFail("Expected find action")
        }
    }

    func testMakeNote() {
        let url = URL(string: "nvenvy://make?title=Hello&txt=Body%20text&tags=swift,mac")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNotNil(action)

        if case .make(let title, let body, let tags) = action!.kind {
            XCTAssertEqual(title, "Hello")
            XCTAssertEqual(body, "Body text")
            XCTAssertEqual(tags, ["swift", "mac"])
        } else {
            XCTFail("Expected make action")
        }
    }

    func testNvSchemeCompat() {
        let url = URL(string: "nv://find/test")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNotNil(action)

        if case .find(let term, _) = action!.kind {
            XCTAssertEqual(term, "test")
        } else {
            XCTFail("Expected find action")
        }
    }

    func testInvalidScheme() {
        let url = URL(string: "https://example.com")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNil(action)
    }

    func testUnknownHost() {
        let url = URL(string: "nvenvy://unknown/path")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNil(action)
    }

    func testEmptyFindPath() {
        let url = URL(string: "nvenvy://find/")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNil(action)
    }

    func testMakeWithMinimalParams() {
        let url = URL(string: "nvenvy://make?title=Test")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNotNil(action)

        if case .make(let title, let body, let tags) = action!.kind {
            XCTAssertEqual(title, "Test")
            XCTAssertNil(body)
            XCTAssertTrue(tags.isEmpty)
        } else {
            XCTFail("Expected make action")
        }
    }
}
