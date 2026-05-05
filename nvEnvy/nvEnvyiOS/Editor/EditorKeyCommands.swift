import UIKit

extension Notification.Name {
    static let nvEnvyFocusSearch = Notification.Name("nvenvy.ios.focusSearch")
    static let nvEnvyNextNote = Notification.Name("nvenvy.ios.nextNote")
    static let nvEnvyPreviousNote = Notification.Name("nvenvy.ios.previousNote")
    static let nvEnvyDeleteSelectedNote = Notification.Name("nvenvy.ios.deleteSelectedNote")
}

final class EditorTextView: UITextView {
    weak var coordinator: EditorCoordinator?

    override var keyCommands: [UIKeyCommand]? {
        let cmds: [(String, UIKeyModifierFlags, Selector)] = [
            ("b", .command, #selector(cmdBold)),
            ("i", .command, #selector(cmdItalic)),
            ("y", .command, #selector(cmdStrikethrough)),
            ("]", .command, #selector(cmdIndent)),
            ("[", .command, #selector(cmdOutdent)),
            ("l", .command, #selector(cmdFocusSearch)),
            ("j", .command, #selector(cmdNextNote)),
            ("k", .command, #selector(cmdPreviousNote)),
        ]
        let base = cmds.map { UIKeyCommand(input: $0.0, modifierFlags: $0.1, action: $0.2) }
        for c in base { c.wantsPriorityOverSystemBehavior = true }
        return (super.keyCommands ?? []) + base
    }

    @objc private func cmdBold() { coordinator?.toggleBold() }
    @objc private func cmdItalic() { coordinator?.toggleItalic() }
    @objc private func cmdStrikethrough() { coordinator?.toggleStrikethrough() }
    @objc private func cmdIndent() { coordinator?.indentSelection() }
    @objc private func cmdOutdent() { coordinator?.outdentSelection() }
    @objc private func cmdFocusSearch() {
        NotificationCenter.default.post(name: .nvEnvyFocusSearch, object: nil)
    }
    @objc private func cmdNextNote() {
        NotificationCenter.default.post(name: .nvEnvyNextNote, object: nil)
    }
    @objc private func cmdPreviousNote() {
        NotificationCenter.default.post(name: .nvEnvyPreviousNote, object: nil)
    }
}
