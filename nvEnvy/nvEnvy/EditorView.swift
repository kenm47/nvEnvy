import SwiftUI
import NvEnvyCore

struct EditorView: View {
    @Environment(AppState.self) private var appState
    let selectedNoteID: Note.ID?

    var body: some View {
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
    }
}

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
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = appState.editorFont
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = context.coordinator

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
        }

        if textView.font != appState.editorFont {
            textView.font = appState.editorFont
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let appState: AppState
        var currentNoteID: Note.ID?
        var isUpdating = false

        init(appState: AppState) {
            self.appState = appState
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView,
                  let noteID = currentNoteID else { return }
            appState.updateNoteBody(noteID: noteID, body: textView.string)
        }
    }
}
