import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NvEnvyCore

struct EditorView: View {
    @Environment(AppState.self) private var appState
    let selectedNoteID: Note.ID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let noteID = selectedNoteID,
                   let note = appState.note(for: noteID) {
                    NoteTextEditor(note: note, appState: appState)
                } else {
                    Text(String(localized: "No note selected"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if appState.showWordCount, let noteID = selectedNoteID,
               let note = appState.note(for: noteID) {
                WordCountOverlay(text: note.body)
                    .padding(8)
            }
        }
    }
}

struct WordCountOverlay: View {
    let text: String
    @State private var stats: (words: Int, chars: Int, lines: Int) = (0, 0, 0)
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        Text("\(stats.words) words | \(stats.chars) chars | \(stats.lines) lines")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Word count: \(stats.words) words, \(stats.chars) characters, \(stats.lines) lines")
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear { computeStats(text) }
            .onChange(of: text) { _, newValue in
                updateTask?.cancel()
                updateTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    computeStats(newValue)
                }
            }
    }

    private func computeStats(_ text: String) {
        let w = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let c = text.count
        let l = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        stats = (w, c, l)
    }
}

// MARK: - NSTextView Editor

struct NoteTextEditor: NSViewRepresentable {
    let note: Note
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = appState.editorFont
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = context.coordinator
        textView.isAutomaticLinkDetectionEnabled = appState.urlDetectionEnabled
        textView.isContinuousSpellCheckingEnabled = appState.checkSpellingEnabled
        textView.textColor = appState.editorFGColor
        textView.backgroundColor = appState.editorBGColor
        textView.baseWritingDirection = appState.rightToLeftText ? .rightToLeft : .leftToRight

        context.coordinator.textView = textView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handlePlainTextStyle(_:)),
            name: .nvEnvyPlainTextStyle,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handlePasteAsMarkdownLink(_:)),
            name: .nvEnvyPasteAsMarkdownLink,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFormatting(_:)),
            name: .nvEnvyFormatting,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFocusEditor(_:)),
            name: .nvEnvyFocusEditor,
            object: nil
        )

        return scrollView
    }

    // MARK: - Scroll jitter prevention
    // Each keystroke triggers: textDidChange → updateNoteBody → @Observable change → updateNSView.
    // To prevent scroll jitter, this method avoids any work that causes full-document layout
    // invalidation during typing. Property sets are guarded with equality checks, wikilink/done
    // highlighting is debounced in textDidChange, and search highlights only run when the query
    // changes. If jitter recurs, check whether new code here touches NSTextStorage attributes
    // on the full document range — that's the trigger.
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        let coordinator = context.coordinator
        let isNoteSwitch = coordinator.currentNoteID != note.id

        if isNoteSwitch {
            coordinator.currentNoteID = note.id
            coordinator.isUpdating = true
            textView.undoManager?.removeAllActions()
            textView.string = note.body
            coordinator.isUpdating = false
            coordinator.lastHighlightedSearchQuery = appState.searchQuery
            // Defer attribute application (wikilinks, search highlights, @done)
            // to after first paint so the text appears instantly on note switch.
            DispatchQueue.main.async {
                coordinator.applyTextAttributes(textView)
            }
            return
        }

        if textView.font != appState.editorFont {
            textView.font = appState.editorFont
        }
        if textView.textColor != appState.editorFGColor {
            textView.textColor = appState.editorFGColor
        }
        if textView.backgroundColor != appState.editorBGColor {
            textView.backgroundColor = appState.editorBGColor
        }
        if textView.isAutomaticLinkDetectionEnabled != appState.urlDetectionEnabled {
            textView.isAutomaticLinkDetectionEnabled = appState.urlDetectionEnabled
        }
        if textView.isContinuousSpellCheckingEnabled != appState.checkSpellingEnabled {
            textView.isContinuousSpellCheckingEnabled = appState.checkSpellingEnabled
        }
        let desiredDirection: NSWritingDirection = appState.rightToLeftText ? .rightToLeft : .leftToRight
        if textView.baseWritingDirection != desiredDirection {
            textView.baseWritingDirection = desiredDirection
        }

        // Only re-run search highlights when the query actually changed
        let searchQueryChanged = coordinator.lastHighlightedSearchQuery != appState.searchQuery
        if searchQueryChanged {
            coordinator.lastHighlightedSearchQuery = appState.searchQuery
            textView.textStorage?.beginEditing()
            coordinator.highlightSearchTerms(in: textView)
            textView.textStorage?.endEditing()
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        let appState: AppState
        var currentNoteID: Note.ID?
        var isUpdating = false
        var lastHighlightedSearchQuery = ""
        var highlightWorkItem: DispatchWorkItem?
        weak var textView: NSTextView?
        var lastEditedRange: NSRange?

        private static let autoPairs: [String: String] = [
            "(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"
        ]

        init(appState: AppState) {
            self.appState = appState
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView,
                  let noteID = currentNoteID else { return }
            appState.updateNoteBody(noteID: noteID, body: textView.string)

            // Capture the edited range for incremental highlighting.
            // Expand to full paragraph(s) so wikilinks/done spanning the edit are caught.
            let editedParagraph: NSRange
            if let edited = lastEditedRange {
                editedParagraph = (textView.string as NSString).paragraphRange(for: edited)
            } else {
                editedParagraph = (textView.string as NSString).paragraphRange(
                    for: textView.selectedRange()
                )
            }
            lastEditedRange = nil

            // Debounced incremental highlight — only processes the edited paragraph,
            // not the full document, avoiding full-layout invalidation.
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let textView = self.textView else { return }
                textView.textStorage?.beginEditing()
                self.highlightWikilinksIncremental(in: textView, range: editedParagraph)
                self.applyDoneStrikethroughIncremental(in: textView, range: editedParagraph)
                textView.textStorage?.endEditing()
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)

            checkWikilinkAutocomplete(in: textView)
        }

        // MARK: - Key handling for auto-behaviors

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleReturn(textView)
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) && appState.softTabs {
                let spaces = String(repeating: " ", count: appState.spacesPerTab)
                textView.insertText(spaces, replacementRange: textView.selectedRange())
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                // Shift+Tab: move focus to the note list
                if let window = textView.window,
                   let tableView = Self.findTableView(in: window.contentView) {
                    window.makeFirstResponder(tableView)
                }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                NotificationCenter.default.post(name: .nvEnvyFocusSearchField, object: nil)
                return true
            }
            return false
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }

            // Track edited range for incremental highlighting
            let newLength = (replacement as NSString).length
            lastEditedRange = NSRange(location: affectedCharRange.location, length: newLength)

            // Auto-pair
            if appState.autoPairEnabled, replacement.count == 1,
               let closing = Coordinator.autoPairs[replacement] {
                let selectedRange = textView.selectedRange()
                if selectedRange.length > 0 {
                    let selectedText = (textView.string as NSString).substring(with: selectedRange)
                    let wrapped = replacement + selectedText + closing
                    textView.insertText(wrapped, replacementRange: selectedRange)
                    textView.setSelectedRange(NSRange(location: selectedRange.location + 1, length: selectedRange.length))
                    return false
                } else {
                    textView.insertText(replacement + closing, replacementRange: affectedCharRange)
                    textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                    return false
                }
            }

            return true
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let linkStr = link as? String, linkStr.hasPrefix("wikilink://") {
                let title = String(linkStr.dropFirst("wikilink://".count))
                    .removingPercentEncoding ?? String(linkStr.dropFirst("wikilink://".count))
                appState.navigateToWikilink(title: title)
                return true
            }
            return false
        }

        // MARK: - Return handling (auto-indent + auto-list)

        private func handleReturn(_ textView: NSTextView) -> Bool {
            let text = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
            let currentLine = text.substring(with: lineRange)

            var insertion = "\n"

            if appState.autoListEnabled {
                if let listContinuation = listContinuation(for: currentLine) {
                    let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed == listContinuation.trimmingCharacters(in: .whitespacesAndNewlines) {
                        textView.insertText("\n", replacementRange: NSRange(location: lineRange.location, length: lineRange.length))
                        return true
                    }
                    insertion = "\n" + listContinuation
                    textView.insertText(insertion, replacementRange: selectedRange)
                    return true
                }
            }

            if appState.autoIndentEnabled {
                let indent = leadingWhitespace(of: currentLine)
                if !indent.isEmpty {
                    insertion = "\n" + indent
                }
            }

            textView.insertText(insertion, replacementRange: selectedRange)
            return true
        }

        private static let unorderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*])\\s")
        private static let orderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)\\.\\s")

        private func listContinuation(for line: String) -> String? {
            let trimmedLine = line.replacingOccurrences(of: "\n", with: "")

            if let match = Self.unorderedListRegex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
                let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
                return indent + marker + " "
            }

            if let match = Self.orderedListRegex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
                let numStr = (trimmedLine as NSString).substring(with: match.range(at: 2))
                if let num = Int(numStr) {
                    return indent + "\(num + 1). "
                }
            }

            return nil
        }

        private func leadingWhitespace(of line: String) -> String {
            var ws = ""
            for ch in line {
                if ch == " " || ch == "\t" {
                    ws.append(ch)
                } else {
                    break
                }
            }
            return ws
        }

        // MARK: - Indent/Outdent

        func handleOutdent(_ textView: NSTextView) -> Bool {
            let text = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = text.lineRange(for: selectedRange)
            let line = text.substring(with: lineRange)

            let tabStr = appState.softTabs ? String(repeating: " ", count: appState.spacesPerTab) : "\t"
            if line.hasPrefix(tabStr) {
                let newLine = String(line.dropFirst(tabStr.count))
                textView.insertText(newLine, replacementRange: lineRange)
                textView.setSelectedRange(NSRange(location: max(lineRange.location, selectedRange.location - tabStr.count), length: 0))
                return true
            }
            return false
        }

        // MARK: - Text Attributes

        func applyTextAttributes(_ textView: NSTextView) {
            textView.textStorage?.beginEditing()
            highlightWikilinks(in: textView)
            highlightSearchTerms(in: textView)
            applyDoneStrikethrough(in: textView)
            textView.textStorage?.endEditing()
        }

        func highlightWikilinks(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            textStorage.removeAttribute(.link, range: fullRange)

            let wikilinks = WikilinkParser.findWikilinkNSRanges(in: text)
            for wl in wikilinks {
                let encodedTitle = wl.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wl.title
                let linkURL = "wikilink://\(encodedTitle)"
                textStorage.addAttribute(.link, value: linkURL, range: wl.range)
            }
        }

        /// Incremental version: only re-highlights wikilinks within the given range.
        func highlightWikilinksIncremental(in textView: NSTextView, range: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            let text = textView.string
            let nsText = text as NSString
            let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: nsText.length))
            guard safeRange.length > 0 else { return }

            textStorage.removeAttribute(.link, range: safeRange)

            let substring = nsText.substring(with: safeRange)
            let wikilinks = WikilinkParser.findWikilinkNSRanges(in: substring)
            for wl in wikilinks {
                let adjustedRange = NSRange(location: wl.range.location + safeRange.location, length: wl.range.length)
                let encodedTitle = wl.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wl.title
                let linkURL = "wikilink://\(encodedTitle)"
                textStorage.addAttribute(.link, value: linkURL, range: adjustedRange)
            }
        }

        func highlightSearchTerms(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            textStorage.removeAttribute(.backgroundColor, range: fullRange)

            guard appState.searchHighlightEnabled,
                  !appState.searchQuery.isEmpty else { return }

            let query = appState.searchQuery.lowercased()
            let nsText = text.lowercased() as NSString
            let color = appState.searchHighlightColor

            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let foundRange = nsText.range(of: query, options: [], range: searchRange)
                guard foundRange.location != NSNotFound else { break }
                textStorage.addAttribute(.backgroundColor, value: color, range: foundRange)
                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = nsText.length - searchRange.location
            }
        }

        // MARK: - @done Strikethrough

        func applyDoneStrikethrough(in textView: NSTextView) {
            guard appState.doneStrikethroughEnabled,
                  let textStorage = textView.textStorage else { return }
            let text = textView.string as NSString
            let fullRange = NSRange(location: 0, length: text.length)

            textStorage.removeAttribute(.strikethroughStyle, range: fullRange)

            text.enumerateSubstrings(in: fullRange, options: .byLines) { line, lineRange, _, _ in
                guard let line else { return }
                if line.contains("@done") {
                    textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
                }
            }
        }

        /// Incremental version: only re-applies @done strikethrough within the given range.
        func applyDoneStrikethroughIncremental(in textView: NSTextView, range: NSRange) {
            guard appState.doneStrikethroughEnabled,
                  let textStorage = textView.textStorage else { return }
            let text = textView.string as NSString
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

        // MARK: - Wikilink Autocomplete

        private var wikilinkMenu: NSMenu?

        func checkWikilinkAutocomplete(in textView: NSTextView) {
            guard appState.autoSuggestWikilinks else { return }

            let text = textView.string as NSString
            let cursorLocation = textView.selectedRange().location

            guard cursorLocation >= 2 else {
                wikilinkMenu?.cancelTracking()
                wikilinkMenu = nil
                return
            }

            // Find [[ before cursor
            var bracketStart: Int?
            var i = cursorLocation - 1
            while i >= 1 {
                let twoChars = text.substring(with: NSRange(location: i - 1, length: 2))
                if twoChars == "[[" {
                    bracketStart = i + 1
                    break
                }
                // If we hit ]] or newline, no open bracket
                if twoChars == "]]" { break }
                let ch = text.character(at: i)
                if ch == 0x0A || ch == 0x0D { break }
                i -= 1
            }

            guard let start = bracketStart, start <= cursorLocation else {
                wikilinkMenu?.cancelTracking()
                wikilinkMenu = nil
                return
            }

            let partial = text.substring(with: NSRange(location: start, length: cursorLocation - start)).lowercased()
            let matches = appState.allNotes
                .filter { $0.cachedLowercaseTitle.contains(partial) }
                .prefix(10)

            guard !matches.isEmpty else {
                wikilinkMenu?.cancelTracking()
                wikilinkMenu = nil
                return
            }

            let menu = NSMenu()
            for note in matches {
                let item = NSMenuItem(title: note.title, action: #selector(insertWikilinkCompletion(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = note.title
                menu.addItem(item)
            }

            let glyphRange = textView.layoutManager?.glyphRange(forCharacterRange: NSRange(location: cursorLocation, length: 0), actualCharacterRange: nil) ?? NSRange(location: cursorLocation, length: 0)
            let rect = textView.layoutManager?.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!) ?? .zero
            let screenPoint = NSPoint(x: rect.origin.x + textView.textContainerInset.width, y: rect.maxY + textView.textContainerInset.height + 4)

            wikilinkMenu?.cancelTracking()
            wikilinkMenu = menu
            menu.popUp(positioning: nil, at: screenPoint, in: textView)
        }

        @objc func insertWikilinkCompletion(_ sender: NSMenuItem) {
            guard let textView = textView,
                  let title = sender.representedObject as? String else { return }

            let text = textView.string as NSString
            let cursor = textView.selectedRange().location

            // Find the [[ before cursor
            var bracketStart: Int?
            var i = cursor - 1
            while i >= 1 {
                let twoChars = text.substring(with: NSRange(location: i - 1, length: 2))
                if twoChars == "[[" {
                    bracketStart = i - 1
                    break
                }
                if twoChars == "]]" { break }
                let ch = text.character(at: i)
                if ch == 0x0A || ch == 0x0D { break }
                i -= 1
            }

            guard let start = bracketStart else { return }
            let replaceRange = NSRange(location: start, length: cursor - start)
            let replacement = "[[\(title)]]"
            textView.insertText(replacement, replacementRange: replaceRange)
            wikilinkMenu = nil
        }

        // MARK: - Insert Link (⌘⇧L)

        func insertLink(in textView: NSTextView) {
            let pasteboard = NSPasteboard.general
            guard let clipboardString = pasteboard.string(forType: .string),
                  let _ = URL(string: clipboardString),
                  clipboardString.hasPrefix("http") else { return }

            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 {
                let selectedText = (textView.string as NSString).substring(with: selectedRange)
                let markdown = "[\(selectedText)](\(clipboardString))"
                textView.insertText(markdown, replacementRange: selectedRange)
            } else {
                let markdown = "[](\(clipboardString))"
                textView.insertText(markdown, replacementRange: selectedRange)
                // Place cursor between the brackets
                textView.setSelectedRange(NSRange(location: selectedRange.location + 1, length: 0))
            }
        }

        // MARK: - Markdown Formatting Commands

        func toggleBold(_ textView: NSTextView) {
            wrapSelection(textView, prefix: "**", suffix: "**")
        }

        func toggleItalic(_ textView: NSTextView) {
            wrapSelection(textView, prefix: "_", suffix: "_")
        }

        func toggleStrikethrough(_ textView: NSTextView) {
            wrapSelection(textView, prefix: "~~", suffix: "~~")
        }

        func indentSelection(_ textView: NSTextView) {
            let tabStr = appState.softTabs ? String(repeating: " ", count: appState.spacesPerTab) : "\t"
            let text = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let lineRange = text.lineRange(for: selectedRange)
            let lines = text.substring(with: lineRange)
            let indented = lines.components(separatedBy: "\n").map { line in
                line.isEmpty ? line : tabStr + line
            }.joined(separator: "\n")
            textView.insertText(indented, replacementRange: lineRange)
        }

        func outdentSelection(_ textView: NSTextView) {
            _ = handleOutdent(textView)
        }

        private func wrapSelection(_ textView: NSTextView, prefix: String, suffix: String) {
            let selectedRange = textView.selectedRange()
            let text = textView.string as NSString

            if selectedRange.length > 0 {
                let selected = text.substring(with: selectedRange)
                if selected.hasPrefix(prefix) && selected.hasSuffix(suffix) && selected.count > prefix.count + suffix.count {
                    let unwrapped = String(selected.dropFirst(prefix.count).dropLast(suffix.count))
                    textView.insertText(unwrapped, replacementRange: selectedRange)
                    textView.setSelectedRange(NSRange(location: selectedRange.location, length: unwrapped.count))
                } else {
                    let wrapped = prefix + selected + suffix
                    textView.insertText(wrapped, replacementRange: selectedRange)
                    textView.setSelectedRange(NSRange(location: selectedRange.location + prefix.count, length: selectedRange.length))
                }
            } else {
                let markers = prefix + suffix
                textView.insertText(markers, replacementRange: selectedRange)
                textView.setSelectedRange(NSRange(location: selectedRange.location + prefix.count, length: 0))
            }
        }

        // MARK: - Formatting Commands

        @objc func handleFormatting(_ notification: Notification) {
            guard let textView = textView,
                  let command = notification.object as? FormattingCommand else { return }
            switch command {
            case .bold: toggleBold(textView)
            case .italic: toggleItalic(textView)
            case .strikethrough: toggleStrikethrough(textView)
            case .indent: indentSelection(textView)
            case .outdent: outdentSelection(textView)
            }
        }

        // MARK: - Plain Text Style

        private static let plainTextRegexes: [(NSRegularExpression, String)] = {
            let patterns: [(String, String)] = [
                ("\\*\\*(.+?)\\*\\*", "$1"),
                ("__(.+?)__", "$1"),
                ("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", "$1"),
                ("(?<!_)_(?!_)(.+?)(?<!_)_(?!_)", "$1"),
                ("~~(.+?)~~", "$1"),
                ("`([^`]+)`", "$1"),
                ("\\[([^\\]]+)\\]\\([^)]+\\)", "$1"),
                ("(?m)^#{1,6}\\s+", ""),
            ]
            return patterns.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
        }()

        @objc func handlePlainTextStyle(_ notification: Notification) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }

            var text = (textView.string as NSString).substring(with: selectedRange)

            for (regex, template) in Self.plainTextRegexes {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
            }

            textView.insertText(text, replacementRange: selectedRange)
        }

        // MARK: - Focus Navigation

        static func findTableView(in view: NSView?) -> NSTableView? {
            guard let view else { return nil }
            if let tableView = view as? NSTableView { return tableView }
            for subview in view.subviews {
                if let found = findTableView(in: subview) { return found }
            }
            return nil
        }

        @objc func handleFocusEditor(_ notification: Notification) {
            guard let textView = textView else { return }
            textView.window?.makeFirstResponder(textView)
        }

        // MARK: - Paste as Markdown Link

        @objc func handlePasteAsMarkdownLink(_ notification: Notification) {
            guard let textView = textView else { return }
            let pasteboard = NSPasteboard.general
            guard let clipboardString = pasteboard.string(forType: .string),
                  let _ = URL(string: clipboardString),
                  clipboardString.hasPrefix("http") else { return }

            let selectedRange = textView.selectedRange()
            let selectedText: String
            if selectedRange.length > 0 {
                selectedText = (textView.string as NSString).substring(with: selectedRange)
            } else {
                selectedText = clipboardString
            }

            let markdown = "[\(selectedText)](\(clipboardString))"
            textView.insertText(markdown, replacementRange: selectedRange)
        }
    }
}
