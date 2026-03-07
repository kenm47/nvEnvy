import SwiftUI
import NvEnvyCore

struct ConflictBanner: View {
    @Environment(AppState.self) private var appState
    @State private var showConflictSheet = false

    private var conflictedNotes: [Note] {
        appState.allNotes.filter { $0.syncStatus == .conflict }
    }

    var body: some View {
        if !conflictedNotes.isEmpty {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(conflictedNotes.count) note\(conflictedNotes.count == 1 ? "" : "s") with sync conflicts")
                    .font(.callout)
                Spacer()
                Button("Resolve...") {
                    showConflictSheet = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.1))
            .sheet(isPresented: $showConflictSheet) {
                ConflictListView(isPresented: $showConflictSheet)
                    .environment(appState)
            }
        }
    }
}

struct ConflictListView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var selectedNote: Note?

    private var conflictedNotes: [Note] {
        appState.allNotes.filter { $0.syncStatus == .conflict }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Sync Conflicts")
                .font(.headline)
                .padding()

            if conflictedNotes.isEmpty {
                Text("No conflicts to resolve.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(conflictedNotes) { note in
                    Button {
                        selectedNote = note
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(note.title)
                                    .font(.body)
                                Text("Modified: \(note.modifiedDate.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
        .sheet(item: $selectedNote) { note in
            ConflictResolutionView(note: note, isPresented: Binding(
                get: { selectedNote != nil },
                set: { if !$0 { selectedNote = nil } }
            ))
            .environment(appState)
        }
    }
}

struct ConflictResolutionView: View {
    @Environment(AppState.self) private var appState
    let note: Note
    @Binding var isPresented: Bool
    @State private var conflictVersions: [ConflictVersion] = []

    struct ConflictVersion: Identifiable {
        let id = UUID()
        let fileVersion: NSFileVersion
        let modifiedDate: Date
        let content: String
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Resolve Conflict: \(note.title)")
                .font(.headline)
                .padding()

            HSplitView {
                // Current version
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Version")
                        .font(.subheadline.bold())
                    Text("Modified: \(note.modifiedDate.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(String(note.body.prefix(500)))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Keep Current") {
                        resolveKeepCurrent()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(minWidth: 250)

                // Conflict versions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conflict Versions")
                        .font(.subheadline.bold())
                    if conflictVersions.isEmpty {
                        Text("No conflict versions found.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(conflictVersions) { version in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Modified: \(version.modifiedDate.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(version.content.prefix(200)))
                                    .font(.caption)
                                    .lineLimit(4)
                                HStack {
                                    Button("Use This Version") {
                                        resolveUseVersion(version)
                                    }
                                    .buttonStyle(.bordered)
                                    Button("Keep Both") {
                                        resolveKeepBoth(version)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .frame(minWidth: 250)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .onAppear { loadConflictVersions() }
    }

    private func loadConflictVersions() {
        guard let folderURL = appState.notesFolderURL else { return }
        let fileURL = folderURL.appendingPathComponent(note.filename + ".md")

        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) else { return }

        conflictVersions = versions.compactMap { version in
            guard let url = version.url as URL? else { return nil }
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return ConflictVersion(
                fileVersion: version,
                modifiedDate: version.modificationDate ?? Date.distantPast,
                content: content
            )
        }
    }

    private func resolveKeepCurrent() {
        guard let folderURL = appState.notesFolderURL else { return }
        let fileURL = folderURL.appendingPathComponent(note.filename + ".md")
        try? NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
        if let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) {
            for version in versions { version.isResolved = true }
        }
        appState.updateSyncStatus(filename: note.filename, status: .current)
        isPresented = false
    }

    private func resolveUseVersion(_ version: ConflictVersion) {
        appState.updateNoteBody(noteID: note.id, body: version.content)
        resolveKeepCurrent()
    }

    private func resolveKeepBoth(_ version: ConflictVersion) {
        let newTitle = note.title + " (conflict)"
        appState.createNoteFromIntent(title: newTitle, body: version.content, tags: note.tags)
        resolveKeepCurrent()
    }
}
