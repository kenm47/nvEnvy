import SwiftUI
import NvEnvyCore

struct TagEditorPanel: View {
    @Environment(AppState.self) private var appState
    let noteID: Note.ID
    @Binding var isPresented: Bool
    @State private var newTag: String = ""
    @State private var suggestions: [String] = []

    private var note: Note? {
        appState.note(for: noteID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.headline)

            // Current tags
            FlowLayout(spacing: 6) {
                ForEach(note?.tags ?? [], id: \.self) { tag in
                    HStack(spacing: 2) {
                        TagPill(tag: tag)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add tag field
            HStack {
                TextField("Add tag...", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                    .onChange(of: newTag) { _, newValue in
                        updateSuggestions(newValue)
                    }

                Button("Add") { addTag() }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Autocomplete suggestions
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                newTag = suggestion
                                addTag()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, let note = note else { return }
        var tags = note.tags
        if !tags.contains(tag) {
            tags.append(tag)
            appState.updateNoteTags(noteID: noteID, tags: tags)
            appState.writeFinderTags(for: note)
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        guard let note = note else { return }
        var tags = note.tags
        tags.removeAll { $0 == tag }
        appState.updateNoteTags(noteID: noteID, tags: tags)
        appState.writeFinderTags(for: note)
    }

    private func updateSuggestions(_ prefix: String) {
        let lower = prefix.lowercased()
        guard !lower.isEmpty else {
            suggestions = []
            return
        }
        let currentTags = Set(note?.tags ?? [])
        suggestions = appState.allKnownTags
            .filter { $0.lowercased().hasPrefix(lower) && !currentTags.contains($0) }
            .prefix(5)
            .map { $0 }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), offsets)
    }
}
