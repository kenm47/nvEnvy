import SwiftUI

struct SearchField: View {
    @Binding var query: String
    var onReturn: () -> Void
    var onEscape: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search or Create", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { onReturn() }
                .onKeyPress(.escape) {
                    onEscape()
                    return .handled
                }
                .accessibilityLabel("Search or Create")
                .accessibilityAddTraits(.isSearchField)

            if !query.isEmpty {
                Button {
                    onEscape()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .onAppear { isFocused = true }
        .background(
            Button("") { isFocused = true }
                .keyboardShortcut("l", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }
}
