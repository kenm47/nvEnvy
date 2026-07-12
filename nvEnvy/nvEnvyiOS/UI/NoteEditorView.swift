import SwiftUI
import UIKit
import NvEnvyCore

struct NoteEditorView: View {
    let note: Note
    let notesVM: NotesViewModel
    @Environment(IOSPreferences.self) private var prefs

    @State private var showingTagEditor = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var renameError: String?
    @State private var pendingDelete = false

    var body: some View {
        NoteUITextEditor(note: note, notesVM: notesVM)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingTagEditor = true
                        } label: {
                            Label("Edit Tags…", systemImage: "tag")
                        }
                        Button {
                            renameText = note.title
                            renaming = true
                        } label: {
                            Label("Rename…", systemImage: "pencil")
                        }
                        Button {
                            UIPasteboard.general.string = note.body
                        } label: {
                            Label("Copy Note", systemImage: "doc.on.doc")
                        }
                        Button {
                            UIPasteboard.general.string = NoteLinkBuilder.link(for: note)
                        } label: {
                            Label("Copy Note Link", systemImage: "link")
                        }
                        Divider()
                        Button(role: .destructive) {
                            requestDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Note actions")
                }
            }
            .sheet(isPresented: $showingTagEditor) {
                TagEditorSheet(noteID: note.id).environment(notesVM)
            }
            .alert("Rename Note", isPresented: $renaming) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let error = notesVM.tryRenameNote(noteID: note.id, newTitle: renameText) {
                        renameError = error
                    }
                }
            }
            .alert("Couldn't Rename", isPresented: Binding(
                get: { renameError != nil },
                set: { if !$0 { renameError = nil } }
            ), presenting: renameError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .confirmationDialog("Delete this note?", isPresented: $pendingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    notesVM.deleteNote(noteID: note.id)
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    private func requestDelete() {
        if prefs.confirmDeletion {
            pendingDelete = true
        } else {
            notesVM.deleteNote(noteID: note.id)
        }
    }
}
