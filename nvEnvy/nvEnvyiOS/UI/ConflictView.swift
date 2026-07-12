import SwiftUI
import NvEnvyCore

/// Touch port of the macOS `ConflictResolutionView.swift` trio (banner / list /
/// resolver). Logic is unchanged — only the layout moves from an `HSplitView`
/// to a scrollable `VStack` for narrow screens.
struct SyncStatusIcon: View {
    let status: SyncStatus

    var body: some View {
        switch status {
        case .local, .current:
            EmptyView()
        case .uploading:
            Image(systemName: "icloud.and.arrow.up")
                .font(.caption2)
                .foregroundStyle(.blue)
                .accessibilityLabel("Uploading")
        case .downloading:
            Image(systemName: "icloud.and.arrow.down")
                .font(.caption2)
                .foregroundStyle(.blue)
                .accessibilityLabel("Downloading")
        case .conflict:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .accessibilityLabel("Sync conflict")
        }
    }
}

struct ConflictBanner: View {
    @Environment(NotesViewModel.self) private var notesVM
    @State private var showConflictSheet = false

    private var conflictedNotes: [Note] {
        notesVM.allNotes.filter { $0.syncStatus == .conflict }
    }

    var body: some View {
        if !conflictedNotes.isEmpty {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(conflictedNotes.count) note\(conflictedNotes.count == 1 ? "" : "s") with sync conflicts")
                    .font(.callout)
                Spacer()
                Button("Resolve…") { showConflictSheet = true }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.1))
            .sheet(isPresented: $showConflictSheet) {
                ConflictListView()
                    .environment(notesVM)
            }
        }
    }
}

struct ConflictListView: View {
    @Environment(NotesViewModel.self) private var notesVM
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNote: Note?

    private var conflictedNotes: [Note] {
        notesVM.allNotes.filter { $0.syncStatus == .conflict }
    }

    var body: some View {
        NavigationStack {
            Group {
                if conflictedNotes.isEmpty {
                    ContentUnavailableView("No Conflicts", systemImage: "checkmark.circle")
                } else {
                    List(conflictedNotes) { note in
                        Button {
                            selectedNote = note
                        } label: {
                            VStack(alignment: .leading) {
                                Text(note.title).font(.body)
                                Text("Modified: \(note.modifiedDate.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sync Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedNote) { note in
                ConflictResolutionView(note: note)
                    .environment(notesVM)
            }
        }
    }
}

struct ConflictResolutionView: View {
    @Environment(NotesViewModel.self) private var notesVM
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var conflictVersions: [ConflictVersion] = []

    struct ConflictVersion: Identifiable {
        let id = UUID()
        let fileVersion: NSFileVersion
        let modifiedDate: Date
        let content: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Version").font(.subheadline.bold())
                        Text("Modified: \(note.modifiedDate.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(note.body.prefix(500)))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Keep Current") { resolveKeepCurrent() }
                            .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Conflict Versions").font(.subheadline.bold())
                        if conflictVersions.isEmpty {
                            Text("No conflict versions found.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(conflictVersions) { version in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Modified: \(version.modifiedDate.formatted())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(String(version.content.prefix(200)))
                                        .font(.caption)
                                        .lineLimit(4)
                                    HStack {
                                        Button("Use This Version") { resolveUseVersion(version) }
                                            .buttonStyle(.bordered)
                                        Button("Keep Both") { resolveKeepBoth(version) }
                                            .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Resolve Conflict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { loadConflictVersions() }
    }

    private func loadConflictVersions() {
        guard let folderURL = notesVM.notesFolderURL else { return }
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
        guard let folderURL = notesVM.notesFolderURL else { return }
        let fileURL = folderURL.appendingPathComponent(note.filename + ".md")
        try? NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
        if let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) {
            for version in versions { version.isResolved = true }
        }
        notesVM.updateSyncStatus(filename: note.filename, status: .current)
        dismiss()
    }

    private func resolveUseVersion(_ version: ConflictVersion) {
        notesVM.updateNoteBody(noteID: note.id, body: version.content)
        resolveKeepCurrent()
    }

    private func resolveKeepBoth(_ version: ConflictVersion) {
        let newTitle = note.title + " (conflict)"
        notesVM.createNoteFromIntent(title: newTitle, body: version.content, tags: note.tags)
        resolveKeepCurrent()
    }
}
