import SwiftUI
import NvEnvyCore

struct NoteReaderView: View {
    let note: Note

    var body: some View {
        ScrollView {
            Text(note.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
