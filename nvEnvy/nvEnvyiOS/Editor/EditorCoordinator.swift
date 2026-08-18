import UIKit
import NvEnvyCore

@MainActor
final class EditorCoordinator: NSObject, UITextViewDelegate {
    let notesVM: NotesViewModel
    let prefs: IOSPreferences
    var currentNoteID: Note.ID?
    var isUpdating = false
    var lastHighlightedSearchQuery = ""
    /// Compared against `IOSPreferences.fontGeneration` so `updateUIView` only
    /// re-applies the font when the font-relevant prefs actually changed.
    var lastAppliedFontGeneration = -1
    weak var textView: UITextView?
    weak var accessoryView: EditorAccessoryView?
    private var lastEditedRange: NSRange?
    private var highlightTask: Task<Void, Never>?

    /// Non-nil while the caret sits inside an unclosed `[[prefix` — drives the
    /// wikilink-suggestion row in the keyboard accessory bar.
    private(set) var wikilinkAutocompletePrefix: String?
    var onWikilinkAutocompleteStateChanged: (() -> Void)?

    private static let autoPairs: [String: String] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"
    ]

    private static let unorderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*])\\s")
    private static let orderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)\\.\\s")

    private var softTabSpaces: Int { prefs.spacesPerTab }
    private static let searchHighlightColor = UIColor.systemYellow.withAlphaComponent(0.4)

    init(notesVM: NotesViewModel, prefs: IOSPreferences) {
        self.notesVM = notesVM
        self.prefs = prefs
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Keyboard avoidance
    //
    // The editor ignores the bottom safe area (`NoteEditorView`) so the text
    // container can extend under the keyboard's resting position; without
    // this the last lines of a long note are unreachable while the keyboard
    // (plus accessory bar) is up, since UITextView doesn't auto-adjust its
    // content inset the way UIScrollView does with `keyboardLayoutGuide`.
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let textView,
              let endFrameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let window = textView.window else { return }

        let endFrameInWindow = endFrameValue.cgRectValue
        let endFrameInView = window.convert(endFrameInWindow, to: textView.superview)
        let overlap = max(0, textView.frame.maxY - endFrameInView.minY)

        textView.contentInset.bottom = overlap
        textView.verticalScrollIndicatorInsets.bottom = overlap
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard !isUpdating, let noteID = currentNoteID else { return }
        notesVM.updateNoteBody(noteID: noteID, body: textView.text ?? "")
        updateWikilinkAutocompleteState(textView)

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
            if self.prefs.doneStrikethrough {
                self.applyDoneStrikethroughIncremental(in: tv, range: editedParagraph)
            }
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
            if prefs.softTabs {
                let spaces = String(repeating: " ", count: softTabSpaces)
                replaceText(textView, in: range, with: spaces, finalSelection: NSRange(location: range.location + spaces.count, length: 0))
                return false
            }
            return true
        }

        // Auto-pair
        if prefs.autoPair, text.count == 1, let closing = Self.autoPairs[text] {
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

    // MARK: - Wikilink autocomplete

    /// Scans backward from the caret for an unclosed `[[prefix`. Mirrors the
    /// detection macOS's `EditorView.checkWikilinkAutocomplete` uses, adapted
    /// to drive the keyboard accessory row instead of an NSMenu popup.
    private func updateWikilinkAutocompleteState(_ textView: UITextView) {
        guard prefs.autoSuggestWikilinks else {
            setWikilinkPrefix(nil)
            return
        }
        let nsText = (textView.text ?? "") as NSString
        let caret = textView.selectedRange.location
        guard caret <= nsText.length else { setWikilinkPrefix(nil); return }

        let searchStart = max(0, caret - 80)
        let preceding = nsText.substring(with: NSRange(location: searchStart, length: caret - searchStart))

        guard let openRange = preceding.range(of: "[[", options: .backwards) else {
            setWikilinkPrefix(nil)
            return
        }
        let afterOpen = String(preceding[openRange.upperBound...])
        if afterOpen.contains("]]") || afterOpen.contains("\n") {
            setWikilinkPrefix(nil)
            return
        }
        setWikilinkPrefix(afterOpen)
    }

    private func setWikilinkPrefix(_ prefix: String?) {
        guard wikilinkAutocompletePrefix != prefix else { return }
        wikilinkAutocompletePrefix = prefix
        onWikilinkAutocompleteStateChanged?()
    }

    func wikilinkSuggestions() -> [String] {
        guard let prefix = wikilinkAutocompletePrefix, !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        return notesVM.sortedNotes
            .map(\.title)
            .filter { $0.lowercased().hasPrefix(lower) }
            .prefix(5)
            .map { $0 }
    }

    func insertWikilinkCompletion(_ title: String) {
        guard let textView, let prefix = wikilinkAutocompletePrefix else { return }
        let caret = textView.selectedRange.location
        let prefixLength = (prefix as NSString).length
        let replaceRange = NSRange(location: caret - prefixLength, length: prefixLength)
        replaceText(textView, in: replaceRange, with: title + "]]",
                    finalSelection: NSRange(location: replaceRange.location + (title as NSString).length + 2, length: 0))
        setWikilinkPrefix(nil)
    }

    func insertWikilinkBrackets() {
        guard let textView else { return }
        let selectedRange = textView.selectedRange
        replaceText(textView, in: selectedRange, with: "[[]]", finalSelection: NSRange(location: selectedRange.location + 2, length: 0))
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

        if prefs.autoList, let listContinuation = listContinuation(for: currentLine) {
            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == listContinuation.trimmingCharacters(in: .whitespacesAndNewlines) {
                replaceText(textView, in: lineRange, with: "\n", finalSelection: NSRange(location: lineRange.location + 1, length: 0))
                return false
            }
            let insertion = "\n" + listContinuation
            replaceText(textView, in: range, with: insertion, finalSelection: NSRange(location: range.location + (insertion as NSString).length, length: 0))
            return false
        }

        if prefs.autoIndent {
            let indent = leadingWhitespace(of: currentLine)
            if !indent.isEmpty {
                let insertion = "\n" + indent
                replaceText(textView, in: range, with: insertion, finalSelection: NSRange(location: range.location + (insertion as NSString).length, length: 0))
                return false
            }
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
        let text = (textView.text ?? "") as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        textStorage.removeAttribute(.backgroundColor, range: fullRange)

        guard prefs.searchHighlight, !notesVM.searchQuery.isEmpty else { return }

        for foundRange in SearchHighlighting.matchRanges(in: text, query: notesVM.searchQuery) {
            textStorage.addAttribute(.backgroundColor, value: Self.searchHighlightColor, range: foundRange)
        }
    }

    func applyDoneStrikethrough(in textView: UITextView) {
        let textStorage = textView.textStorage
        let text = (textView.text ?? "") as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        textStorage.removeAttribute(.strikethroughStyle, range: fullRange)
        guard prefs.doneStrikethrough else { return }

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
        let tabStr = String(repeating: " ", count: softTabSpaces)
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
        let tabStr = String(repeating: " ", count: softTabSpaces)
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
