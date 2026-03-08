import SwiftUI

struct SearchField: View {
    @Binding var query: String
    var onReturn: () -> Void
    var onEscape: () -> Void
    var onDownArrow: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(String(localized: "Search or Create"), text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { onReturn() }
                .onKeyPress(.escape) {
                    onEscape()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onDownArrow()
                    isFocused = false
                    // Find the NSTableView (backing SwiftUI List) and make it first responder
                    DispatchQueue.main.async {
                        if let window = NSApp.keyWindow,
                           let tableView = Self.findTableView(in: window.contentView) {
                            window.makeFirstResponder(tableView)
                        }
                    }
                    return .handled
                }
                .accessibilityLabel(String(localized: "Search or Create"))
                .accessibilityAddTraits(.isSearchField)

            if !query.isEmpty {
                Button {
                    onEscape()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
                .accessibilityHint(String(localized: "Double-tap to clear the search field"))
            }
        }
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .onAppear { isFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyFocusSearchField)) { _ in
            isFocused = true
        }
        .background(
            Button("") { isFocused = true }
                .keyboardShortcut("l", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }

    private static func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tableView = view as? NSTableView { return tableView }
        for subview in view.subviews {
            if let found = findTableView(in: subview) { return found }
        }
        return nil
    }
}
