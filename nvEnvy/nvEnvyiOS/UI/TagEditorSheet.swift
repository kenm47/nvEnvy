import SwiftUI
import NvEnvyCore

/// Touch port of the single-note editor from macOS `TagEditorPanel.swift`.
/// Finder-tag mirroring is skipped — no-op on iOS already.
struct TagEditorSheet: View {
    @Environment(NotesViewModel.self) private var notesVM
    @Environment(\.dismiss) private var dismiss
    let noteID: Note.ID
    @State private var newTag: String = ""
    @State private var suggestions: [String] = []

    private var note: Note? { notesVM.note(for: noteID) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
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

                HStack {
                    TextField("Add tag…", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { addTag() }
                        .onChange(of: newTag) { _, newValue in updateSuggestions(newValue) }
                        .accessibilityLabel("Add tag")

                    Button("Add") { addTag() }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }

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

                Spacer()
            }
            .padding()
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, let note else { return }
        var tags = note.tags
        if !tags.contains(tag) {
            tags.append(tag)
            notesVM.updateNoteTags(noteID: noteID, tags: tags)
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        guard let note else { return }
        var tags = note.tags
        tags.removeAll { $0 == tag }
        notesVM.updateNoteTags(noteID: noteID, tags: tags)
    }

    private func updateSuggestions(_ prefix: String) {
        let lower = prefix.lowercased()
        guard !lower.isEmpty else {
            suggestions = []
            return
        }
        let currentTags = Set(note?.tags ?? [])
        suggestions = notesVM.allKnownTags
            .filter { $0.lowercased().hasPrefix(lower) && !currentTags.contains($0) }
            .prefix(5)
            .map { $0 }
    }
}

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor.opacity(0.2), in: Capsule())
            .foregroundStyle(tagColor)
            .accessibilityLabel(tag)
    }

    private var tagColor: Color {
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .indigo]
        return colors[hash % colors.count]
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
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
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + rowHeight), offsets)
    }
}
