import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
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
    // Pre-compiled regexes for HTML processing
    private static let scriptRegex = try! NSRegularExpression(pattern: "<script[^>]*>[\\s\\S]*?</script>")
    private static let styleRegex = try! NSRegularExpression(pattern: "<style[^>]*>[\\s\\S]*?</style>")
    private static let brRegex = try! NSRegularExpression(pattern: "<br[^>]*>")
    private static let tagRegex = try! NSRegularExpression(pattern: "<[^>]+>")
    private static let multiNewlineRegex = try! NSRegularExpression(pattern: "\n{3,}")
    private static let h1Regex = try! NSRegularExpression(pattern: "<h1[^>]*>(.*?)</h1>")
    private static let h2Regex = try! NSRegularExpression(pattern: "<h2[^>]*>(.*?)</h2>")
    private static let h3Regex = try! NSRegularExpression(pattern: "<h3[^>]*>(.*?)</h3>")
    private static let h4Regex = try! NSRegularExpression(pattern: "<h4[^>]*>(.*?)</h4>")
    private static let h5Regex = try! NSRegularExpression(pattern: "<h5[^>]*>(.*?)</h5>")
    private static let h6Regex = try! NSRegularExpression(pattern: "<h6[^>]*>(.*?)</h6>")
    private static let boldRegex = try! NSRegularExpression(pattern: "<(strong|b)>(.*?)</\\1>")
    private static let italicRegex = try! NSRegularExpression(pattern: "<(em|i)>(.*?)</\\1>")
    private static let codeRegex = try! NSRegularExpression(pattern: "<code>(.*?)</code>")
    private static let preCodeRegex = try! NSRegularExpression(pattern: "<pre[^>]*><code[^>]*>(.*?)</code></pre>")
    private static let preRegex = try! NSRegularExpression(pattern: "<pre[^>]*>(.*?)</pre>")
    private static let linkRegex = try! NSRegularExpression(pattern: "<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>")
    private static let imgAltSrcRegex = try! NSRegularExpression(pattern: "<img[^>]*alt=\"([^\"]*)\"[^>]*src=\"([^\"]*)\"[^>]*/?>")
    private static let imgSrcAltRegex = try! NSRegularExpression(pattern: "<img[^>]*src=\"([^\"]*)\"[^>]*alt=\"([^\"]*)\"[^>]*/?>")
    private static let imgSrcRegex = try! NSRegularExpression(pattern: "<img[^>]*src=\"([^\"]*)\"[^>]*/?>")
    private static let liRegex = try! NSRegularExpression(pattern: "<li[^>]*>(.*?)</li>")
    private static let listWrapperRegex = try! NSRegularExpression(pattern: "</?[uo]l[^>]*>")
    private static let pOpenRegex = try! NSRegularExpression(pattern: "<p[^>]*>")
    private static let brCloseRegex = try! NSRegularExpression(pattern: "<br[^>]*/?>")
    private static let navRegex = try! NSRegularExpression(pattern: "<nav[^>]*>[\\s\\S]*?</nav>")
    private static let asideRegex = try! NSRegularExpression(pattern: "<aside[^>]*>[\\s\\S]*?</aside>")
    private static let footerRegex = try! NSRegularExpression(pattern: "<footer[^>]*>[\\s\\S]*?</footer>")
    private static let headerRegex = try! NSRegularExpression(pattern: "<header[^>]*>[\\s\\S]*?</header>")
    private static let articleRegex = try! NSRegularExpression(pattern: "<article[^>]*>([\\s\\S]*?)</article>")
    private static let divRegex = try! NSRegularExpression(pattern: "<div[^>]*>([\\s\\S]*?)</div>")

    public static let supportedExtensions: Set<String> = [
        "txt", "text", "utf8", "md", "markdown", "mmd", "rtf", "rtfd", "htm", "html",
        "pdf", "doc", "docx", "webarchive"
    ]

    public init() {}

    // MARK: - Import File

    public func importFile(at url: URL) throws -> ImportedNote {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent

        // RTFD is a directory bundle — handle before reading data
        if ext == "rtfd" {
            return try Self.importRTFD(at: url, title: title)
        }

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

        case "webarchive":
            return try Self.importWebArchive(at: url, title: title)

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

    #if canImport(AppKit) || canImport(UIKit)
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

    // MARK: - RTFD Import

    private static func importRTFD(at url: URL, title: String) throws -> ImportedNote {
        #if canImport(AppKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]
        if let attrStr = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
            return ImportedNote(title: title, body: attrStr.string)
        }
        throw ImportExportError.encodingError
        #else
        throw ImportExportError.unsupportedFormat("rtfd")
        #endif
    }

    // MARK: - Web Archive Import

    private static func importWebArchive(at url: URL, title: String) throws -> ImportedNote {
        #if canImport(AppKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.webArchive
        ]
        if let attrStr = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
            return ImportedNote(title: title, body: attrStr.string)
        }
        throw ImportExportError.encodingError
        #else
        throw ImportExportError.unsupportedFormat("webarchive")
        #endif
    }

    // MARK: - Word Export

    #if canImport(AppKit)
    public func exportAsWord(_ note: Note) -> Data? {
        let attrStr = NSAttributedString(string: note.body)
        return try? attrStr.data(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.docFormat]
        )
    }
    #endif

    // MARK: - HTML Stripping

    private static func regexReplace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    public static func stripHTML(_ html: String) -> String {
        var text = html
        text = regexReplace(scriptRegex, in: text, with: "")
        text = regexReplace(styleRegex, in: text, with: "")
        text = regexReplace(brRegex, in: text, with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = text.replacingOccurrences(of: "</div>", with: "\n")
        text = text.replacingOccurrences(of: "</li>", with: "\n")
        text = regexReplace(tagRegex, in: text, with: "")

        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = regexReplace(multiNewlineRegex, in: text, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTML to Markdown

    public static func htmlToMarkdown(_ html: String) -> String {
        var text = html

        // Remove script and style blocks
        text = regexReplace(scriptRegex, in: text, with: "")
        text = regexReplace(styleRegex, in: text, with: "")

        // Headings
        let headingRegexes = [h1Regex, h2Regex, h3Regex, h4Regex, h5Regex, h6Regex]
        for (i, regex) in headingRegexes.enumerated() {
            let prefix = String(repeating: "#", count: i + 1)
            text = regexReplace(regex, in: text, with: "\n\n\(prefix) $1\n\n")
        }

        // Bold
        text = regexReplace(boldRegex, in: text, with: "**$2**")
        // Italic
        text = regexReplace(italicRegex, in: text, with: "_$2_")
        // Code
        text = regexReplace(codeRegex, in: text, with: "`$1`")
        // Pre/code blocks
        text = regexReplace(preCodeRegex, in: text, with: "\n\n```\n$1\n```\n\n")
        text = regexReplace(preRegex, in: text, with: "\n\n```\n$1\n```\n\n")

        // Links
        text = regexReplace(linkRegex, in: text, with: "[$2]($1)")
        // Images
        text = regexReplace(imgAltSrcRegex, in: text, with: "![$1]($2)")
        text = regexReplace(imgSrcAltRegex, in: text, with: "![$2]($1)")
        text = regexReplace(imgSrcRegex, in: text, with: "![]($1)")

        // List items
        text = regexReplace(liRegex, in: text, with: "- $1\n")
        // Remove list wrappers
        text = regexReplace(listWrapperRegex, in: text, with: "\n")

        // Paragraphs
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = regexReplace(pOpenRegex, in: text, with: "")

        // Line breaks
        text = regexReplace(brCloseRegex, in: text, with: "\n")

        // Divs
        text = text.replacingOccurrences(of: "</div>", with: "\n")

        // Strip remaining tags
        text = regexReplace(tagRegex, in: text, with: "")

        // Decode entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }

        // Normalize whitespace
        text = regexReplace(multiNewlineRegex, in: text, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Readability Extraction

    public static func extractArticleContent(_ html: String) -> String {
        var text = html

        // Remove nav, sidebar, footer, header, script, style
        let removeRegexes = [navRegex, asideRegex, footerRegex, headerRegex, scriptRegex, styleRegex]
        for regex in removeRegexes {
            text = regexReplace(regex, in: text, with: "")
        }

        // Try to find <article> content first
        if let match = articleRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = Range(match.range(at: 1), in: text)!
            return String(text[range])
        }

        // Find the largest <div> block by text content length
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

        return text
    }

    // MARK: - RTF Conversion

    private static func convertRTFToPlainText(_ data: Data) -> String {
        #if canImport(AppKit) || canImport(UIKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        if let attrStr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
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
