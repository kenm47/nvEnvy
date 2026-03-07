import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif

public struct ImportedNote: Sendable {
    public let title: String
    public let body: String
    public let tags: [String]

    public init(title: String, body: String, tags: [String] = []) {
        self.title = title
        self.body = body
        self.tags = tags
    }
}

public actor ImportExportService {

    public static let supportedExtensions: Set<String> = [
        "txt", "text", "utf8", "md", "markdown", "mmd", "rtf", "htm", "html",
        "pdf", "doc", "docx"
    ]

    public init() {}

    // MARK: - Import File

    public func importFile(at url: URL) throws -> ImportedNote {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        let data = try Data(contentsOf: url)

        switch ext {
        case "md", "markdown", "mmd":
            guard let content = String(data: data, encoding: .utf8) else {
                throw ImportExportError.encodingError
            }
            let parsed = FrontmatterParser.parse(content)
            return ImportedNote(title: title, body: parsed.body, tags: parsed.frontmatter?.tags ?? [])

        case "txt", "text", "utf8":
            guard let content = String(data: data, encoding: .utf8) else {
                throw ImportExportError.encodingError
            }
            return ImportedNote(title: title, body: content)

        case "htm", "html":
            guard let content = String(data: data, encoding: .utf8) else {
                throw ImportExportError.encodingError
            }
            return ImportedNote(title: title, body: Self.stripHTML(content))

        case "rtf":
            let text = Self.convertRTFToPlainText(data)
            return ImportedNote(title: title, body: text)

        case "pdf":
            return try Self.importPDF(at: url, title: title)

        case "doc", "docx":
            return try Self.importWord(at: url, title: title)

        default:
            throw ImportExportError.unsupportedFormat(ext)
        }
    }

    // MARK: - Import Directory

    public func importDirectory(at url: URL) throws -> [ImportedNote] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [ImportedNote] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            if let note = try? importFile(at: fileURL) {
                results.append(note)
            }
        }
        return results
    }

    // MARK: - Import URL

    public func importURLContent(_ url: URL, useReadability: Bool = true, convertToMarkdown: Bool = true) async throws -> ImportedNote {
        let (data, response) = try await URLSession.shared.data(from: url)
        let title = url.host ?? url.lastPathComponent

        if let http = response as? HTTPURLResponse,
           let ct = http.value(forHTTPHeaderField: "Content-Type"),
           ct.contains("text/html"),
           let html = String(data: data, encoding: .utf8) {
            var content = html
            if useReadability {
                content = Self.extractArticleContent(content)
            }
            if convertToMarkdown {
                content = Self.htmlToMarkdown(content)
            } else {
                content = Self.stripHTML(content)
            }
            return ImportedNote(title: title, body: content)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportExportError.encodingError
        }
        return ImportedNote(title: title, body: text)
    }

    // MARK: - Import Pasteboard Data

    public func importPlainText(_ text: String, title: String) -> ImportedNote {
        ImportedNote(title: title, body: text)
    }

    public func importRTFData(_ data: Data, title: String) -> ImportedNote {
        let text = Self.convertRTFToPlainText(data)
        return ImportedNote(title: title, body: text)
    }

    public func importHTMLString(_ html: String, title: String) -> ImportedNote {
        ImportedNote(title: title, body: Self.stripHTML(html))
    }

    // MARK: - Export

    public func exportAsPlainText(_ note: Note) -> String {
        note.body
    }

    public func exportAsHTML(_ note: Note) -> String {
        MarkdownRenderer.renderHTML(from: note.body, title: note.title)
    }

    #if canImport(AppKit)
    public func exportAsRTF(_ note: Note) -> Data? {
        let attrStr = NSAttributedString(string: note.body)
        return try? attrStr.data(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
    #endif

    // MARK: - PDF Import

    private static func importPDF(at url: URL, title: String) throws -> ImportedNote {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url),
              let text = document.string, !text.isEmpty else {
            throw ImportExportError.encodingError
        }
        return ImportedNote(title: title, body: text)
        #else
        throw ImportExportError.unsupportedFormat("pdf")
        #endif
    }

    // MARK: - Word Import

    private static func importWord(at url: URL, title: String) throws -> ImportedNote {
        #if canImport(AppKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.docFormat
        ]
        if let attrStr = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
            return ImportedNote(title: title, body: attrStr.string)
        }
        // Try as plain attributed string (handles .docx via default handler)
        if let attrStr = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            return ImportedNote(title: title, body: attrStr.string)
        }
        throw ImportExportError.encodingError
        #else
        throw ImportExportError.unsupportedFormat("doc")
        #endif
    }

    // MARK: - HTML Stripping

    public static func stripHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = text.replacingOccurrences(of: "</div>", with: "\n")
        text = text.replacingOccurrences(of: "</li>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML to Markdown

    public static func htmlToMarkdown(_ html: String) -> String {
        var text = html

        // Remove script and style blocks
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Headings
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            text = text.replacingOccurrences(
                of: "<h\(level)[^>]*>(.*?)</h\(level)>",
                with: "\n\n\(prefix) $1\n\n",
                options: .regularExpression
            )
        }

        // Bold
        text = text.replacingOccurrences(of: "<(strong|b)>(.*?)</\\1>", with: "**$2**", options: .regularExpression)
        // Italic
        text = text.replacingOccurrences(of: "<(em|i)>(.*?)</\\1>", with: "_$2_", options: .regularExpression)
        // Code
        text = text.replacingOccurrences(of: "<code>(.*?)</code>", with: "`$1`", options: .regularExpression)
        // Pre/code blocks
        text = text.replacingOccurrences(of: "<pre[^>]*><code[^>]*>(.*?)</code></pre>", with: "\n\n```\n$1\n```\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<pre[^>]*>(.*?)</pre>", with: "\n\n```\n$1\n```\n\n", options: .regularExpression)

        // Links
        text = text.replacingOccurrences(of: "<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>", with: "[$2]($1)", options: .regularExpression)
        // Images
        text = text.replacingOccurrences(of: "<img[^>]*alt=\"([^\"]*)\"[^>]*src=\"([^\"]*)\"[^>]*/?>", with: "![$1]($2)", options: .regularExpression)
        text = text.replacingOccurrences(of: "<img[^>]*src=\"([^\"]*)\"[^>]*alt=\"([^\"]*)\"[^>]*/?>", with: "![$2]($1)", options: .regularExpression)
        text = text.replacingOccurrences(of: "<img[^>]*src=\"([^\"]*)\"[^>]*/?>", with: "![]($1)", options: .regularExpression)

        // List items
        text = text.replacingOccurrences(of: "<li[^>]*>(.*?)</li>", with: "- $1\n", options: .regularExpression)
        // Remove list wrappers
        text = text.replacingOccurrences(of: "</?[uo]l[^>]*>", with: "\n", options: .regularExpression)

        // Paragraphs
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = text.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)

        // Line breaks
        text = text.replacingOccurrences(of: "<br[^>]*/?>", with: "\n", options: .regularExpression)

        // Divs
        text = text.replacingOccurrences(of: "</div>", with: "\n")

        // Strip remaining tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }

        // Normalize whitespace
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Readability Extraction

    public static func extractArticleContent(_ html: String) -> String {
        var text = html

        // Remove nav, sidebar, footer, header, script, style
        let removePatterns = [
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<aside[^>]*>[\\s\\S]*?</aside>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
        ]
        for pattern in removePatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Try to find <article> content first
        if let articleRegex = try? NSRegularExpression(pattern: "<article[^>]*>([\\s\\S]*?)</article>", options: []),
           let match = articleRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = Range(match.range(at: 1), in: text)!
            return String(text[range])
        }

        // Find the largest <div> block by text content length
        if let divRegex = try? NSRegularExpression(pattern: "<div[^>]*>([\\s\\S]*?)</div>", options: []) {
            let matches = divRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            var bestContent = ""
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let content = String(text[range])
                    let stripped = stripHTML(content)
                    if stripped.count > bestContent.count {
                        bestContent = content
                    }
                }
            }
            if !bestContent.isEmpty {
                return bestContent
            }
        }

        return text
    }

    // MARK: - RTF Conversion

    private static func convertRTFToPlainText(_ data: Data) -> String {
        #if canImport(AppKit)
        if let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attrStr.string
        }
        #endif
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
    }
}

public enum ImportExportError: Error, LocalizedError {
    case encodingError
    case unsupportedFormat(String)
    case exportError(String)

    public var errorDescription: String? {
        switch self {
        case .encodingError: return "Failed to decode file content"
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext)"
        case .exportError(let msg): return "Export error: \(msg)"
        }
    }
}
