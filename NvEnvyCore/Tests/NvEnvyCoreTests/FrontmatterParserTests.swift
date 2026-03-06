import XCTest
@testable import NvEnvyCore

final class FrontmatterParserTests: XCTestCase {

    // MARK: - Parse Tests

    func testParseNoFrontmatter() {
        let content = "Hello world\nThis is a note."
        let result = FrontmatterParser.parse(content)
        XCTAssertNil(result.frontmatter)
        XCTAssertEqual(result.body, content)
    }

    func testParseEmptyContent() {
        let result = FrontmatterParser.parse("")
        XCTAssertNil(result.frontmatter)
        XCTAssertEqual(result.body, "")
    }

    func testParseBasicFrontmatter() {
        let content = "---\ntags:\n  - swift\n  - macos\n---\nHello world"
        let result = FrontmatterParser.parse(content)
        XCTAssertNotNil(result.frontmatter)
        XCTAssertEqual(result.frontmatter?.tags, ["swift", "macos"])
        XCTAssertEqual(result.body, "Hello world")
    }

    func testParseFlowStyleTags() {
        let content = "---\ntags: [swift, macos]\n---\nBody text"
        let result = FrontmatterParser.parse(content)
        XCTAssertEqual(result.frontmatter?.tags, ["swift", "macos"])
        XCTAssertEqual(result.body, "Body text")
    }

    func testUnknownKeyPreservation() {
        let content = "---\ntags:\n  - test\naliases: [my-alias]\ncssclasses: custom\n---\nBody"
        let result = FrontmatterParser.parse(content)
        XCTAssertEqual(result.frontmatter?.tags, ["test"])
        XCTAssertEqual(result.frontmatter?.unknownFields.count, 2)
        XCTAssertEqual(result.frontmatter?.unknownFields[0].key, "aliases")
        XCTAssertEqual(result.frontmatter?.unknownFields[1].key, "cssclasses")
    }

    func testKeyOrderPreservation() {
        let content = "---\ncustom_z: z\ncustom_a: a\ncustom_m: m\n---\nBody"
        let result = FrontmatterParser.parse(content)
        let keys = result.frontmatter?.unknownFields.map(\.key) ?? []
        XCTAssertEqual(keys, ["custom_z", "custom_a", "custom_m"])
    }

    func testEmptyFrontmatterRemoval() {
        let fm = FrontmatterBlock(tags: [], created: nil, modified: nil, unknownFields: [])
        let result = FrontmatterParser.serialize(frontmatter: fm, body: "Hello")
        XCTAssertEqual(result, "Hello")
    }

    func testUnclosedFrontmatter() {
        let content = "---\ntags:\n  - test\nNo closing delimiter"
        let result = FrontmatterParser.parse(content)
        XCTAssertNil(result.frontmatter)
        XCTAssertEqual(result.body, content)
    }

    // MARK: - Round-Trip Tests

    func testRoundTripWithTags() {
        let original = "---\ntags:\n  - swift\n  - macos\n---\nHello world"
        let parsed = FrontmatterParser.parse(original)
        let serialized = FrontmatterParser.serialize(frontmatter: parsed.frontmatter, body: parsed.body)
        let reparsed = FrontmatterParser.parse(serialized)

        XCTAssertEqual(reparsed.frontmatter?.tags, parsed.frontmatter?.tags)
        XCTAssertEqual(reparsed.body, parsed.body)
    }

    func testRoundTripUnknownFields() {
        let original = "---\ntags:\n  - test\naliases: my-alias\npublish: true\n---\nBody text"
        let parsed = FrontmatterParser.parse(original)
        let serialized = FrontmatterParser.serialize(frontmatter: parsed.frontmatter, body: parsed.body)
        let reparsed = FrontmatterParser.parse(serialized)

        XCTAssertEqual(reparsed.frontmatter?.tags, ["test"])
        XCTAssertEqual(reparsed.frontmatter?.unknownFields.count, 2)
        XCTAssertEqual(reparsed.frontmatter?.unknownFields[0].key, "aliases")
        XCTAssertEqual(reparsed.frontmatter?.unknownFields[1].key, "publish")
        XCTAssertEqual(reparsed.body, "Body text")
    }

    // MARK: - Serialize Tests

    func testSerializeNilFrontmatter() {
        let result = FrontmatterParser.serialize(frontmatter: nil, body: "Just body")
        XCTAssertEqual(result, "Just body")
    }

    func testSerializeWithDates() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let fm = FrontmatterBlock(tags: ["test"], created: date, modified: date)
        let result = FrontmatterParser.serialize(frontmatter: fm, body: "Body")
        XCTAssertTrue(result.hasPrefix("---\n"))
        XCTAssertTrue(result.contains("tags:"))
        XCTAssertTrue(result.contains("  - test"))
        XCTAssertTrue(result.contains("created:"))
        XCTAssertTrue(result.contains("modified:"))
        XCTAssertTrue(result.hasSuffix("---\nBody"))
    }
}
