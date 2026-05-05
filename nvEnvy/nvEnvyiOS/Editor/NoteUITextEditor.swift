import SwiftUI
import UIKit
import NvEnvyCore

struct NoteUITextEditor: UIViewRepresentable {
    let note: Note
    let notesVM: NotesViewModel

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(notesVM: notesVM)
    }

    func makeUIView(context: Context) -> EditorTextView {
        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: EditorTextView, context: Context) {
        let coordinator = context.coordinator
        let isNoteSwitch = coordinator.currentNoteID != note.id

        if isNoteSwitch {
            coordinator.currentNoteID = note.id
            coordinator.isUpdating = true
            textView.text = note.body
            coordinator.isUpdating = false
            coordinator.lastHighlightedSearchQuery = notesVM.searchQuery
            DispatchQueue.main.async {
                coordinator.applyTextAttributes(textView)
            }
            return
        }

        let searchQueryChanged = coordinator.lastHighlightedSearchQuery != notesVM.searchQuery
        if searchQueryChanged {
            coordinator.lastHighlightedSearchQuery = notesVM.searchQuery
            textView.textStorage.beginEditing()
            coordinator.highlightSearchTerms(in: textView)
            textView.textStorage.endEditing()
        }
    }
}
