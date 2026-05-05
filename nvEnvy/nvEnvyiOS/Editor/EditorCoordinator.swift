import UIKit
import NvEnvyCore

@MainActor
final class EditorCoordinator: NSObject, UITextViewDelegate {
    let notesVM: NotesViewModel
    var currentNoteID: Note.ID?
    var isUpdating = false
    var lastHighlightedSearchQuery = ""
    weak var textView: UITextView?
    private var lastEditedRange: NSRange?
    private var highlightTask: Task<Void, Never>?

    private static let autoPairs: [String: String] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"
    ]

    private static let unorderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*])\\s")
    private static let orderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)\\.\\s")

    private static let softTabSpaces = 4
    private static let searchHighlightColor = UIColor.systemYellow.withAlphaComponent(0.4)

    init(notesVM: NotesViewModel) {
        self.notesVM = notesVM
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard !isUpdating, let noteID = currentNoteID else { return }
        notesVM.updateNoteBody(noteID: noteID, body: textView.text ?? "")

        let editedParagraph: NSRange
        let nsText = (textView.text ?? "") as NSString
        if let edited = lastEditedRange {
            let safe = NSIntersectionRange(edited, NSRange(location: 0, length: nsText.length))
            editedParagraph = safe.length > 0 ? nsText.paragraphRange(for: safe) : NSRange(location: 0, length: 0)
        } else {
            editedParagraph = nsText.paragraphRange(for: textView.selectedRange)
        }
        lastEditedRange = nil

        highlightTask?.cancel()
        highlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let tv = self.textView else { return }
            tv.textStorage.beginEditing()
            self.highlightWikilinksIncremental(in: tv, range: editedParagraph)
            self.applyDoneStrikethroughIncremental(in: tv, range: editedParagraph)
            tv.textStorage.endEditing()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let newLength = (text as NSString).length
        lastEditedRange = NSRange(location: range.location, length: newLength)

        // Return key — auto-list / auto-indent
        if text == "\n" {
            return handleReturn(textView, in: range)
        }

        // Tab — soft-tabs
        if text == "\t" {
            let spaces = String(repeating: " ", count: Self.softTabSpaces)
            replaceText(textView, in: range, with: spaces, finalSelection: NSRange(location: range.location + spaces.count, length: 0))
            return false
        }

        // Auto-pair
        if text.count == 1, let closing = Self.autoPairs[text] {
            if range.length > 0 {
                let nsText = (textView.text ?? "") as NSString
                let selectedText = nsText.substring(with: range)
                let wrapped = text + selectedText + closing
                replaceText(textView, in: range, with: wrapped, finalSelection: NSRange(location: range.location + 1, length: range.length))
                return false
            } else {
                let pair = text + closing
                replaceText(textView, in: range, with: pair, finalSelection: NSRange(location: range.location + 1, length: 0))
                return false
            }
        }

        return true
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if URL.scheme == "wikilink" {
            let host = URL.host ?? ""
            let path = URL.path
            let combined = host + path
            let title = combined.removingPercentEncoding ?? combined
            notesVM.navigateToWikilink(title: title)
            return false
        }
        return true
    }

    // MARK: - Return handling

    private func handleReturn(_ textView: UITextView, in range: NSRange) -> Bool {
        let text = (textView.text ?? "") as NSString
        let lineRange = text.lineRange(for: NSRange(location: range.location, length: 0))
        let currentLine = text.substring(with: lineRange)

        if let listContinuation = listContinuation(for: currentLine) {
            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == listContinuation.trimmingCharacters(in: .whitespacesAndNewlines) {
                replaceText(textView, in: lineRange, with: "\n", finalSelection: NSRange(location: lineRange.location + 1, length: 0))
                return false
            }
            let insertion = "\n" + listContinuation
            replaceText(textView, in: range, with: insertion, finalSelection: NSRange(location: range.location + (insertion as NSString).length, length: 0))
            return false
        }

        let indent = leadingWhitespace(of: currentLine)
        if !indent.isEmpty {
            let insertion = "\n" + indent
            replaceText(textView, in: range, with: insertion, finalSelection: NSRange(location: range.location + (insertion as NSString).length, length: 0))
            return false
        }

        return true
    }

    private func listContinuation(for line: String) -> String? {
        let trimmedLine = line.replacingOccurrences(of: "\n", with: "")
        let nsLine = trimmedLine as NSString
        let lineRange = NSRange(location: 0, length: nsLine.length)

        if let match = Self.unorderedListRegex.firstMatch(in: trimmedLine, range: lineRange) {
            let indent = nsLine.substring(with: match.range(at: 1))
            let marker = nsLine.substring(with: match.range(at: 2))
            return indent + marker + " "
        }

        if let match = Self.orderedListRegex.firstMatch(in: trimmedLine, range: lineRange) {
            let indent = nsLine.substring(with: match.range(at: 1))
            let numStr = nsLine.substring(with: match.range(at: 2))
            if let num = Int(numStr) {
                return indent + "\(num + 1). "
            }
        }

        return nil
    }

    private func leadingWhitespace(of line: String) -> String {
        var ws = ""
        for ch in line {
            if ch == " " || ch == "\t" { ws.append(ch) } else { break }
        }
        return ws
    }

    // MARK: - Replace helper (manual edit because we returned false)

    private func replaceText(_ textView: UITextView, in range: NSRange, with replacement: String, finalSelection: NSRange) {
        guard let textRange = textView.textRange(from: textView.position(from: textView.beginningOfDocument, offset: range.location) ?? textView.beginningOfDocument,
                                                  to: textView.position(from: textView.beginningOfDocument, offset: range.location + range.length) ?? textView.beginningOfDocument)
        else { return }
        textView.replace(textRange, withText: replacement)
        textView.selectedRange = finalSelection
    }

    // MARK: - Text Attributes (lifted from macOS EditorView)

    func applyTextAttributes(_ textView: UITextView) {
        textView.textStorage.beginEditing()
        highlightWikilinks(in: textView)
        highlightSearchTerms(in: textView)
        applyDoneStrikethrough(in: textView)
        textView.textStorage.endEditing()
    }

    func highlightWikilinks(in textView: UITextView) {
        let textStorage = textView.textStorage
        let text = textView.text ?? ""
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        textStorage.removeAttribute(.link, range: fullRange)

        let wikilinks = WikilinkParser.findWikilinkNSRanges(in: text)
        for wl in wikilinks {
            let encodedTitle = wl.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wl.title
            if let url = URL(string: "wikilink://\(encodedTitle)") {
                textStorage.addAttribute(.link, value: url, range: wl.range)
            }
        }
    }

    func highlightWikilinksIncremental(in textView: UITextView, range: NSRange) {
        let textStorage = textView.textStorage
        let text = textView.text ?? ""
        let nsText = text as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: nsText.length))
        guard safeRange.length > 0 else { return }

        textStorage.removeAttribute(.link, range: safeRange)

        let substring = nsText.substring(with: safeRange)
        let wikilinks = WikilinkParser.findWikilinkNSRanges(in: substring)
        for wl in wikilinks {
            let adjustedRange = NSRange(location: wl.range.location + safeRange.location, length: wl.range.length)
            let encodedTitle = wl.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wl.title
            if let url = URL(string: "wikilink://\(encodedTitle)") {
                textStorage.addAttribute(.link, value: url, range: adjustedRange)
            }
        }
    }

    func highlightSearchTerms(in textView: UITextView) {
        let textStorage = textView.textStorage
        let text = textView.text ?? ""
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        textStorage.removeAttribute(.backgroundColor, range: fullRange)

        guard !notesVM.searchQuery.isEmpty else { return }

        let query = notesVM.searchQuery.lowercased()
        let nsText = text.lowercased() as NSString

        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: query, options: [], range: searchRange)
            guard foundRange.location != NSNotFound else { break }
            textStorage.addAttribute(.backgroundColor, value: Self.searchHighlightColor, range: foundRange)
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }
    }

    func applyDoneStrikethrough(in textView: UITextView) {
        let textStorage = textView.textStorage
        let text = (textView.text ?? "") as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        textStorage.removeAttribute(.strikethroughStyle, range: fullRange)

        text.enumerateSubstrings(in: fullRange, options: .byLines) { line, lineRange, _, _ in
            guard let line else { return }
            if line.contains("@done") {
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
            }
        }
    }

    func applyDoneStrikethroughIncremental(in textView: UITextView, range: NSRange) {
        let textStorage = textView.textStorage
        let text = (textView.text ?? "") as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard safeRange.length > 0 else { return }

        textStorage.removeAttribute(.strikethroughStyle, range: safeRange)

        text.enumerateSubstrings(in: safeRange, options: .byLines) { line, lineRange, _, _ in
            guard let line else { return }
            if line.contains("@done") {
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
            }
        }
    }

    // MARK: - Formatting (used by key commands)

    func toggleBold() { wrapSelection(prefix: "**", suffix: "**") }
    func toggleItalic() { wrapSelection(prefix: "_", suffix: "_") }
    func toggleStrikethrough() { wrapSelection(prefix: "~~", suffix: "~~") }

    func indentSelection() {
        guard let textView else { return }
        let tabStr = String(repeating: " ", count: Self.softTabSpaces)
        let text = (textView.text ?? "") as NSString
        let selectedRange = textView.selectedRange
        let lineRange = text.lineRange(for: selectedRange)
        let lines = text.substring(with: lineRange)
        let indented = lines.components(separatedBy: "\n").map { line in
            line.isEmpty ? line : tabStr + line
        }.joined(separator: "\n")
        replaceText(textView, in: lineRange, with: indented, finalSelection: NSRange(location: lineRange.location, length: (indented as NSString).length))
    }

    func outdentSelection() {
        guard let textView else { return }
        let tabStr = String(repeating: " ", count: Self.softTabSpaces)
        let text = (textView.text ?? "") as NSString
        let selectedRange = textView.selectedRange
        let lineRange = text.lineRange(for: selectedRange)
        let line = text.substring(with: lineRange)
        if line.hasPrefix(tabStr) {
            let newLine = String(line.dropFirst(tabStr.count))
            replaceText(textView, in: lineRange, with: newLine, finalSelection: NSRange(location: max(lineRange.location, selectedRange.location - tabStr.count), length: 0))
        }
    }

    private func wrapSelection(prefix: String, suffix: String) {
        guard let textView else { return }
        let selectedRange = textView.selectedRange
        let text = (textView.text ?? "") as NSString

        if selectedRange.length > 0 {
            let selected = text.substring(with: selectedRange)
            if selected.hasPrefix(prefix) && selected.hasSuffix(suffix) && selected.count > prefix.count + suffix.count {
                let unwrapped = String(selected.dropFirst(prefix.count).dropLast(suffix.count))
                replaceText(textView, in: selectedRange, with: unwrapped, finalSelection: NSRange(location: selectedRange.location, length: (unwrapped as NSString).length))
            } else {
                let wrapped = prefix + selected + suffix
                replaceText(textView, in: selectedRange, with: wrapped, finalSelection: NSRange(location: selectedRange.location + (prefix as NSString).length, length: selectedRange.length))
            }
        } else {
            let markers = prefix + suffix
            replaceText(textView, in: selectedRange, with: markers, finalSelection: NSRange(location: selectedRange.location + (prefix as NSString).length, length: 0))
        }
    }
}
