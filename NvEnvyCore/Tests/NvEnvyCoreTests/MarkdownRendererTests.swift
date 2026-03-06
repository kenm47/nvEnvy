import XCTest
@testable import NvEnvyCore

final class MarkdownRendererTests: XCTestCase {

    func testBasicParagraph() {
        let html = MarkdownRenderer.renderBodyHTML(from: "Hello world")
        XCTAssertTrue(html.contains("<p>Hello world</p>"))
    }

    func testHeadings() {
        let html = MarkdownRenderer.renderBodyHTML(from: "# Title\n## Subtitle")
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<h2>Subtitle</h2>"))
    }

    func testBoldAndItalic() {
        let html = MarkdownRenderer.renderBodyHTML(from: "**bold** and _italic_")
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
    }

    func testCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let html = MarkdownRenderer.renderBodyHTML(from: md)
        XCTAssertTrue(html.contains("<pre>"))
        XCTAssertTrue(html.contains("<code"))
        XCTAssertTrue(html.contains("let x = 1"))
    }

    func testInlineCode() {
        let html = MarkdownRenderer.renderBodyHTML(from: "Use `print()`")
        XCTAssertTrue(html.contains("<code>print()</code>"))
    }

    func testLink() {
        let html = MarkdownRenderer.renderBodyHTML(from: "[Apple](https://apple.com)")
        XCTAssertTrue(html.contains("<a href=\"https://apple.com\">Apple</a>"))
    }

    func testUnorderedList() {
        let md = "- one\n- two\n- three"
        let html = MarkdownRenderer.renderBodyHTML(from: md)
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>"))
    }

    func testOrderedList() {
        let md = "1. first\n2. second"
        let html = MarkdownRenderer.renderBodyHTML(from: md)
        XCTAssertTrue(html.contains("<ol>"))
    }

    func testBlockquote() {
        let html = MarkdownRenderer.renderBodyHTML(from: "> A quote")
        XCTAssertTrue(html.contains("<blockquote>"))
    }

    func testFullHTML() {
        let html = MarkdownRenderer.renderHTML(from: "# Test", title: "My Note")
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<title>My Note</title>"))
        XCTAssertTrue(html.contains("<h1 class=\"doctitle\">My Note</h1>"))
        XCTAssertTrue(html.contains("<h1>Test</h1>"))
    }

    func testHTMLEscaping() {
        let html = MarkdownRenderer.renderHTML(from: "Test", title: "<script>alert('xss')</script>")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testStrikethrough() {
        let html = MarkdownRenderer.renderBodyHTML(from: "~~deleted~~")
        XCTAssertTrue(html.contains("<del>deleted</del>"))
    }

    func testImage() {
        let html = MarkdownRenderer.renderBodyHTML(from: "![Alt](image.png)")
        XCTAssertTrue(html.contains("<img src=\"image.png\""))
        XCTAssertTrue(html.contains("alt=\"Alt\""))
    }

    func testThematicBreak() {
        let html = MarkdownRenderer.renderBodyHTML(from: "---")
        XCTAssertTrue(html.contains("<hr>"))
    }

    func testEmptyInput() {
        let html = MarkdownRenderer.renderBodyHTML(from: "")
        XCTAssertTrue(html.isEmpty || html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
