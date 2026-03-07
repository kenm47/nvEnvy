import XCTest
@testable import NvEnvyCore

final class ImportExportServiceTests: XCTestCase {
    var tempDir: URL!
    var service: ImportExportService!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ImportExportService()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Plain Text Import

    func testImportPlainText() async throws {
        let file = tempDir.appendingPathComponent("hello.txt")
        try "Hello world".write(to: file, atomically: true, encoding: .utf8)

        let imported = try await service.importFile(at: file)
        XCTAssertEqual(imported.title, "hello")
        XCTAssertEqual(imported.body, "Hello world")
        XCTAssertTrue(imported.tags.isEmpty)
    }

    // MARK: - Markdown Import

    func testImportMarkdownWithFrontmatter() async throws {
        let file = tempDir.appendingPathComponent("note.md")
        try "---\ntags:\n  - swift\n  - mac\n---\nSome content".write(to: file, atomically: true, encoding: .utf8)

        let imported = try await service.importFile(at: file)
        XCTAssertEqual(imported.title, "note")
        XCTAssertEqual(imported.body, "Some content")
        XCTAssertEqual(imported.tags, ["swift", "mac"])
    }

    func testImportMarkdownPlain() async throws {
        let file = tempDir.appendingPathComponent("plain.markdown")
        try "# Title\n\nBody text".write(to: file, atomically: true, encoding: .utf8)

        let imported = try await service.importFile(at: file)
        XCTAssertEqual(imported.title, "plain")
        XCTAssertEqual(imported.body, "# Title\n\nBody text")
    }

    // MARK: - HTML Import

    func testImportHTML() async throws {
        let file = tempDir.appendingPathComponent("page.html")
        let html = "<html><body><p>Hello</p><p>World</p></body></html>"
        try html.write(to: file, atomically: true, encoding: .utf8)

        let imported = try await service.importFile(at: file)
        XCTAssertEqual(imported.title, "page")
        XCTAssertTrue(imported.body.contains("Hello"))
        XCTAssertTrue(imported.body.contains("World"))
    }

    // MARK: - HTML Stripping

    func testStripHTML() {
        let html = "<p>Hello &amp; <strong>World</strong></p>"
        let stripped = ImportExportService.stripHTML(html)
        XCTAssertEqual(stripped, "Hello & World")
    }

    func testStripHTMLScriptsRemoved() {
        let html = "<p>Before</p><script>alert('x')</script><p>After</p>"
        let stripped = ImportExportService.stripHTML(html)
        XCTAssertTrue(stripped.contains("Before"))
        XCTAssertTrue(stripped.contains("After"))
        XCTAssertFalse(stripped.contains("alert"))
    }

    // MARK: - Directory Import

    func testImportDirectory() async throws {
        let file1 = tempDir.appendingPathComponent("one.txt")
        let file2 = tempDir.appendingPathComponent("two.md")
        let file3 = tempDir.appendingPathComponent("skip.jpg")
        try "Text one".write(to: file1, atomically: true, encoding: .utf8)
        try "Text two".write(to: file2, atomically: true, encoding: .utf8)
        try "Not imported".write(to: file3, atomically: true, encoding: .utf8)

        let results = try await service.importDirectory(at: tempDir)
        XCTAssertEqual(results.count, 2)

        let titles = Set(results.map(\.title))
        XCTAssertTrue(titles.contains("one"))
        XCTAssertTrue(titles.contains("two"))
    }

    // MARK: - Unsupported Format

    func testUnsupportedFormat() async {
        let file = tempDir.appendingPathComponent("image.png")
        try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

        do {
            _ = try await service.importFile(at: file)
            XCTFail("Should throw for unsupported format")
        } catch let error as ImportExportError {
            if case .unsupportedFormat(let ext) = error {
                XCTAssertEqual(ext, "png")
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Export Round-Trip

    func testExportPlainTextRoundTrip() async throws {
        // Create a note, export as text, re-import
        let note = Note(title: "Round Trip", body: "Hello round trip", tags: ["test"])

        let text = await service.exportAsPlainText(note)
        XCTAssertEqual(text, "Hello round trip")

        let file = tempDir.appendingPathComponent("roundtrip.txt")
        try text.write(to: file, atomically: true, encoding: .utf8)

        let reimported = try await service.importFile(at: file)
        XCTAssertEqual(reimported.body, note.body)
    }

    func testExportHTMLContainsBody() async {
        let note = Note(title: "HTML Test", body: "Some **bold** text")
        let html = await service.exportAsHTML(note)
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("HTML Test"))
    }

    // MARK: - Pasteboard Import Helpers

    func testImportPlainTextHelper() async {
        let imported = await service.importPlainText("Note content", title: "Pasted Note")
        XCTAssertEqual(imported.title, "Pasted Note")
        XCTAssertEqual(imported.body, "Note content")
    }

    func testImportHTMLStringHelper() async {
        let imported = await service.importHTMLString("<p>Hello</p>", title: "HTML Paste")
        XCTAssertEqual(imported.title, "HTML Paste")
        XCTAssertEqual(imported.body, "Hello")
    }

    // MARK: - HTML to Markdown

    func testHTMLToMarkdownHeadings() {
        let html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
        let md = ImportExportService.htmlToMarkdown(html)
        XCTAssertTrue(md.contains("# Title"))
        XCTAssertTrue(md.contains("## Subtitle"))
        XCTAssertTrue(md.contains("### Section"))
    }

    func testHTMLToMarkdownFormatting() {
        let html = "<strong>bold</strong> and <em>italic</em> and <code>code</code>"
        let md = ImportExportService.htmlToMarkdown(html)
        XCTAssertTrue(md.contains("**bold**"))
        XCTAssertTrue(md.contains("_italic_"))
        XCTAssertTrue(md.contains("`code`"))
    }

    func testHTMLToMarkdownLinks() {
        let html = "<a href=\"https://example.com\">Example</a>"
        let md = ImportExportService.htmlToMarkdown(html)
        XCTAssertTrue(md.contains("[Example](https://example.com)"))
    }

    func testHTMLToMarkdownListItems() {
        let html = "<ul><li>First</li><li>Second</li></ul>"
        let md = ImportExportService.htmlToMarkdown(html)
        XCTAssertTrue(md.contains("- First"))
        XCTAssertTrue(md.contains("- Second"))
    }

    func testHTMLToMarkdownStripsScripts() {
        let html = "<p>Content</p><script>alert('x')</script>"
        let md = ImportExportService.htmlToMarkdown(html)
        XCTAssertTrue(md.contains("Content"))
        XCTAssertFalse(md.contains("alert"))
    }

    // MARK: - Readability Extraction

    func testExtractArticleContent() {
        let html = """
        <html><body>
        <nav>Navigation</nav>
        <article>Main article content here</article>
        <footer>Footer info</footer>
        </body></html>
        """
        let extracted = ImportExportService.extractArticleContent(html)
        XCTAssertTrue(extracted.contains("Main article content"))
        XCTAssertFalse(extracted.contains("Navigation"))
        XCTAssertFalse(extracted.contains("Footer"))
    }

    // MARK: - RTFD Import

    func testImportRTFDBundle() async throws {
        // Create a minimal RTFD bundle programmatically
        let rtfdDir = tempDir.appendingPathComponent("test.rtfd")
        try FileManager.default.createDirectory(at: rtfdDir, withIntermediateDirectories: true)

        // Write a simple RTF file inside the bundle
        let rtfContent = "{\\rtf1\\ansi\\pard Hello from RTFD\\par}"
        let rtfFile = rtfdDir.appendingPathComponent("TXT.rtf")
        try rtfContent.write(to: rtfFile, atomically: true, encoding: .utf8)

        let imported = try await service.importFile(at: rtfdDir)
        XCTAssertEqual(imported.title, "test")
        XCTAssertTrue(imported.body.contains("Hello from RTFD"))
    }

    // MARK: - Word Export

    func testExportAsWordRoundTrip() async throws {
        let note = Note(title: "Word Test", body: "Word export content")
        let data = await service.exportAsWord(note)
        XCTAssertNotNil(data)

        // Write and re-import
        let file = tempDir.appendingPathComponent("exported.doc")
        try data!.write(to: file)

        let reimported = try await service.importFile(at: file)
        XCTAssertTrue(reimported.body.contains("Word export content"))
    }

    func testExtractArticleContentFallsBackToLargestDiv() {
        let html = """
        <html><body>
        <script>var x = 1;</script>
        <div>Short</div>
        <div>This is a much longer div with lots of content that should be selected as the main content block</div>
        </body></html>
        """
        let extracted = ImportExportService.extractArticleContent(html)
        XCTAssertTrue(extracted.contains("much longer div"))
    }
}
