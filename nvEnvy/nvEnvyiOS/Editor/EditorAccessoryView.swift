import UIKit

/// Keyboard accessory bar hosting touch equivalents of the hardware-keyboard
/// formatting shortcuts (`EditorKeyCommands.swift`), since most iOS editing
/// happens without a hardware keyboard. Swaps to a horizontal row of wikilink
/// title suggestions while the caret sits inside an unclosed `[[prefix`
/// (driven by `EditorCoordinator.wikilinkAutocompletePrefix`).
final class EditorAccessoryView: UIView {
    private weak var coordinator: EditorCoordinator?
    private weak var textView: UITextView?

    private let formattingBar = UIToolbar()
    private let suggestionsScroll = UIScrollView()
    private let suggestionsStack = UIStackView()

    init(coordinator: EditorCoordinator, textView: UITextView) {
        self.coordinator = coordinator
        self.textView = textView
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        autoresizingMask = .flexibleWidth
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true

        setUpFormattingBar()
        setUpSuggestionsRow()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUpFormattingBar() {
        formattingBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formattingBar)
        NSLayoutConstraint.activate([
            formattingBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            formattingBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            formattingBar.topAnchor.constraint(equalTo: topAnchor),
            formattingBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let wikilink = UIBarButtonItem(title: "[[ ]]", style: .plain, target: self, action: #selector(insertWikilink))
        let bold = UIBarButtonItem(image: UIImage(systemName: "bold"), style: .plain, target: self, action: #selector(toggleBold))
        let italic = UIBarButtonItem(image: UIImage(systemName: "italic"), style: .plain, target: self, action: #selector(toggleItalic))
        let strike = UIBarButtonItem(image: UIImage(systemName: "strikethrough"), style: .plain, target: self, action: #selector(toggleStrikethrough))
        let outdent = UIBarButtonItem(image: UIImage(systemName: "decrease.indent"), style: .plain, target: self, action: #selector(outdent))
        let indent = UIBarButtonItem(image: UIImage(systemName: "increase.indent"), style: .plain, target: self, action: #selector(indent))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let dismiss = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), style: .plain, target: self, action: #selector(dismissKeyboard))

        wikilink.accessibilityLabel = "Insert wikilink"
        bold.accessibilityLabel = "Bold"
        italic.accessibilityLabel = "Italic"
        strike.accessibilityLabel = "Strikethrough"
        outdent.accessibilityLabel = "Decrease indent"
        indent.accessibilityLabel = "Increase indent"
        dismiss.accessibilityLabel = "Dismiss keyboard"

        formattingBar.items = [wikilink, bold, italic, strike, outdent, indent, flex, dismiss]
    }

    private func setUpSuggestionsRow() {
        suggestionsScroll.translatesAutoresizingMaskIntoConstraints = false
        suggestionsScroll.showsHorizontalScrollIndicator = false
        addSubview(suggestionsScroll)
        NSLayoutConstraint.activate([
            suggestionsScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            suggestionsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            suggestionsScroll.topAnchor.constraint(equalTo: topAnchor),
            suggestionsScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        suggestionsStack.axis = .horizontal
        suggestionsStack.spacing = 8
        suggestionsStack.alignment = .center
        suggestionsStack.translatesAutoresizingMaskIntoConstraints = false
        suggestionsScroll.addSubview(suggestionsStack)
        NSLayoutConstraint.activate([
            suggestionsStack.leadingAnchor.constraint(equalTo: suggestionsScroll.leadingAnchor, constant: 12),
            suggestionsStack.trailingAnchor.constraint(equalTo: suggestionsScroll.trailingAnchor, constant: -12),
            suggestionsStack.topAnchor.constraint(equalTo: suggestionsScroll.topAnchor),
            suggestionsStack.bottomAnchor.constraint(equalTo: suggestionsScroll.bottomAnchor),
            suggestionsStack.heightAnchor.constraint(equalTo: suggestionsScroll.heightAnchor),
        ])
    }

    /// Rebuilds the suggestions row (if active) and toggles which bar is
    /// visible. Called whenever the coordinator's autocomplete state changes.
    func refresh() {
        guard let coordinator else { return }
        let suggestions = coordinator.wikilinkSuggestions()
        let isSuggesting = coordinator.wikilinkAutocompletePrefix != nil && !suggestions.isEmpty

        formattingBar.isHidden = isSuggesting
        suggestionsScroll.isHidden = !isSuggesting

        suggestionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for title in suggestions {
            var config = UIButton.Configuration.bordered()
            config.title = title
            config.cornerStyle = .capsule
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
                self?.coordinator?.insertWikilinkCompletion(title)
            })
            suggestionsStack.addArrangedSubview(button)
        }
    }

    @objc private func insertWikilink() { coordinator?.insertWikilinkBrackets() }
    @objc private func toggleBold() { coordinator?.toggleBold() }
    @objc private func toggleItalic() { coordinator?.toggleItalic() }
    @objc private func toggleStrikethrough() { coordinator?.toggleStrikethrough() }
    @objc private func indent() { coordinator?.indentSelection() }
    @objc private func outdent() { coordinator?.outdentSelection() }
    @objc private func dismissKeyboard() { textView?.resignFirstResponder() }
}
