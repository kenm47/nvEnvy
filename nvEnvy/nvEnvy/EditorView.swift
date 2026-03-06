import SwiftUI
import AppKit
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
                    Text("No note selected")
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

        context.coordinator.textView = textView

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
        textView.textColor = appState.editorFGColor
        textView.backgroundColor = appState.editorBGColor
        textView.isAutomaticLinkDetectionEnabled = appState.urlDetectionEnabled
        textView.isContinuousSpellCheckingEnabled = appState.checkSpellingEnabled

        coordinator.highlightSearchTerms(in: textView)
        coordinator.highlightWikilinks(in: textView)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        let appState: AppState
        var currentNoteID: Note.ID?
        var isUpdating = false
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
            appState.updateNoteBody(noteID: noteID, body: textView.string)
            highlightWikilinks(in: textView)
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
    }
}
