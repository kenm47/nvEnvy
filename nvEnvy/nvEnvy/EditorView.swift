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

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
    private var charCount: Int { text.count }
    private var lineCount: Int {
        text.isEmpty ? 0 : text.components(separatedBy: "\n").count
    }

    var body: some View {
        Text("\(wordCount) words | \(charCount) chars | \(lineCount) lines")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Word count: \(wordCount) words, \(charCount) characters, \(lineCount) lines")
            .accessibilityAddTraits(.updatesFrequently)
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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        let coordinator = context.coordinator

        if coordinator.currentNoteID != note.id {
            coordinator.currentNoteID = note.id
            coordinator.isUpdating = true
            textView.undoManager?.removeAllActions()
            textView.string = note.body
            coordinator.isUpdating = false
            coordinator.applyTextAttributes(textView)
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

        if !coordinator.isLocalEdit {
            coordinator.highlightSearchTerms(in: textView)
            coordinator.highlightWikilinks(in: textView)
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        let appState: AppState
        var currentNoteID: Note.ID?
        var isUpdating = false
        var isLocalEdit = false
        weak var textView: NSTextView?

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
            isLocalEdit = true
            appState.updateNoteBody(noteID: noteID, body: textView.string)
            highlightWikilinks(in: textView)
            applyDoneStrikethrough(in: textView)
            checkWikilinkAutocomplete(in: textView)
            DispatchQueue.main.async { [weak self] in
                self?.isLocalEdit = false
            }
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
                return handleOutdent(textView)
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                NotificationCenter.default.post(name: .nvEnvyFocusSearchField, object: nil)
                return true
            }
            return false
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }

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

        private func listContinuation(for line: String) -> String? {
            let trimmedLine = line.replacingOccurrences(of: "\n", with: "")

            let unorderedPattern = "^(\\s*)([-*])\\s"
            if let regex = try? NSRegularExpression(pattern: unorderedPattern),
               let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                let indent = (trimmedLine as NSString).substring(with: match.range(at: 1))
                let marker = (trimmedLine as NSString).substring(with: match.range(at: 2))
                return indent + marker + " "
            }

            let orderedPattern = "^(\\s*)(\\d+)\\.\\s"
            if let regex = try? NSRegularExpression(pattern: orderedPattern),
               let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
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
            highlightWikilinks(in: textView)
            highlightSearchTerms(in: textView)
            applyDoneStrikethrough(in: textView)
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

        @objc func handlePlainTextStyle(_ notification: Notification) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }

            var text = (textView.string as NSString).substring(with: selectedRange)

            // Strip bold **text** or __text__
            text = text.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            text = text.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)
            // Strip italic _text_ or *text*
            text = text.replacingOccurrences(of: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", with: "$1", options: .regularExpression)
            text = text.replacingOccurrences(of: "(?<!_)_(?!_)(.+?)(?<!_)_(?!_)", with: "$1", options: .regularExpression)
            // Strip strikethrough ~~text~~
            text = text.replacingOccurrences(of: "~~(.+?)~~", with: "$1", options: .regularExpression)
            // Strip inline code `text`
            text = text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
            // Strip link syntax [text](url) → text
            text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            // Strip heading prefixes
            text = text.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)

            textView.insertText(text, replacementRange: selectedRange)
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
