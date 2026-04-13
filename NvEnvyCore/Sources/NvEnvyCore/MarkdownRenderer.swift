import Foundation
import Markdown

public enum MarkdownRenderer {
    public static func renderHTML(from markdown: String, title: String = "", customCSS: String? = nil) -> String {
        let document = Document(parsing: markdown)
        var htmlVisitor = HTMLVisitor()
        let bodyHTML = htmlVisitor.visit(document)

        var css = defaultCSS
        if let custom = customCSS {
            css += "\n" + custom
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapeHTML(title))</title>
        <style>\(css)</style>
        </head>
        <body>
        <h1 class="doctitle">\(escapeHTML(title))</h1>
        <div id="contentdiv">\(bodyHTML)</div>
        </body>
        </html>
        """
    }

    public static func renderBodyHTML(from markdown: String) -> String {
        let document = Document(parsing: markdown)
        var htmlVisitor = HTMLVisitor()
        return htmlVisitor.visit(document)
    }

    static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    public static let defaultCSS = """
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        line-height: 1.6;
        padding: 20px 40px;
        max-width: 800px;
        margin: 0 auto;
        color: #333;
        background: #fff;
    }
    @media (prefers-color-scheme: dark) {
        body { color: #e0e0e0; background: #1e1e1e; }
        a { color: #6cb6ff; }
        code { background: #2d2d2d; }
        pre { background: #2d2d2d; }
        blockquote { border-color: #444; }
    }
    h1.doctitle {
        font-size: 1.8em;
        border-bottom: 1px solid #ddd;
        padding-bottom: 0.3em;
    }
    h1, h2, h3, h4, h5, h6 { margin-top: 1.2em; margin-bottom: 0.5em; }
    code {
        font-family: "SF Mono", Menlo, Consolas, monospace;
        font-size: 0.9em;
        background: #f5f5f5;
        padding: 2px 5px;
        border-radius: 3px;
    }
    pre {
        background: #f5f5f5;
        padding: 12px;
        border-radius: 6px;
        overflow-x: auto;
    }
    pre code { background: none; padding: 0; }
    blockquote {
        border-left: 4px solid #ddd;
        margin: 0;
        padding: 0 16px;
        color: #666;
    }
    img { max-width: 100%; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background: #f5f5f5; }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    @media print {
        body { padding: 0; max-width: none; }
        h1.doctitle { font-size: 1.5em; }
    }
    """
}

// Simple HTML visitor for swift-markdown
private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: any Markup) -> String {
        var result = ""
        for child in markup.children {
            result += visit(child)
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> String {
        defaultVisit(document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>" + defaultVisit(paragraph) + "</p>\n"
    }

    mutating func visitText(_ text: Markdown.Text) -> String {
        escapeHTML(text.string)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = heading.level
        return "<h\(level)>" + defaultVisit(heading) + "</h\(level)>\n"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>" + defaultVisit(emphasis) + "</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>" + defaultVisit(strong) + "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>" + defaultVisit(strikethrough) + "</del>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let href = link.destination ?? ""
        return "<a href=\"\(escapeHTML(href))\">" + defaultVisit(link) + "</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let src = image.source ?? ""
        let alt = image.plainText
        return "<img src=\"\(escapeHTML(src))\" alt=\"\(escapeHTML(alt))\">"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language ?? ""
        let code = escapeHTML(codeBlock.code)
        if lang.isEmpty {
            return "<pre><code>" + code + "</code></pre>\n"
        }
        return "<pre><code class=\"language-\(escapeHTML(lang))\">" + code + "</code></pre>\n"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>" + escapeHTML(inlineCode.code) + "</code>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n" + defaultVisit(blockQuote) + "</blockquote>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n" + defaultVisit(unorderedList) + "</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        "<ol>\n" + defaultVisit(orderedList) + "</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        "<li>" + defaultVisit(listItem) + "</li>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        html.rawHTML
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitTable(_ table: Markdown.Table) -> String {
        "<table>\n" + defaultVisit(table) + "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Markdown.Table.Head) -> String {
        "<thead>\n<tr>\n" + defaultVisit(tableHead) + "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Markdown.Table.Body) -> String {
        "<tbody>\n" + defaultVisit(tableBody) + "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Markdown.Table.Row) -> String {
        "<tr>\n" + defaultVisit(tableRow) + "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Markdown.Table.Cell) -> String {
        let tag = tableCell.parent is Markdown.Table.Head ? "th" : "td"
        return "<\(tag)>" + defaultVisit(tableCell) + "</\(tag)>\n"
    }

    private func escapeHTML(_ string: String) -> String {
        MarkdownRenderer.escapeHTML(string)
    }
}
