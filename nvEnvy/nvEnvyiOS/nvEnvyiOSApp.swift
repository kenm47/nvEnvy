import SwiftUI
import UIKit
import NvEnvyCore

@main
struct nvEnvyiOSApp: App {
    @State private var notesVM = NotesViewModel()
    @State private var folderProvider = NotesFolderProvider()
    @State private var prefs = IOSPreferences()
    @State private var folderResolved = false
    @State private var folderMonitor: IOSFolderMonitor?
    /// The very first `.active` scenePhase transition coincides with cold
    /// launch, where `attach()`'s own load just did a full scan — a second
    /// `reconcileFilesystem()` right after would redundantly re-scan the
    /// whole vault, costly for large vaults (thousands of files). Every
    /// subsequent `.active` transition (a real background→foreground resume)
    /// still reconciles normally.
    @State private var hasSeenFirstActiveTransition = false
    @Environment(\.scenePhase) private var scenePhase

    private static let lastSelectedNoteIDKey = "nvenvy.iOS.lastSelectedNoteID"

    var body: some Scene {
        WindowGroup {
            Group {
                if folderResolved, notesVM.notesFolderURL != nil {
                    RootSplitView()
                        .environment(notesVM)
                        .environment(prefs)
                        .environment(folderProvider)
                } else {
                    FirstLaunchView(folderProvider: folderProvider) { url in
                        attach(url: url)
                    }
                }
            }
            .preferredColorScheme(prefs.appearance.colorScheme)
            .onAppear {
                if let url = folderProvider.resolveSavedBookmark() {
                    attach(url: url)
                }
            }
            .onOpenURL { url in
                notesVM.handleURL(url)
            }
            .onChange(of: notesVM.selectedNoteID) { _, newValue in
                UserDefaults.standard.set(newValue?.uuidString, forKey: Self.lastSelectedNoteIDKey)
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nvEnvyFolderChanged)) { notification in
                guard let url = notification.object as? URL else { return }
                attach(url: url)
            }
        }
    }

    private func attach(url: URL) {
        folderMonitor?.stop()
        folderMonitor = nil
        notesVM.attach(
            folderURL: url,
            coordinator: NSFileCoordinatorAdapter()
        ) {
            restoreLastSelection()
            startFolderMonitor(url: url)
        }
        folderResolved = true
    }

    private func restoreLastSelection() {
        guard let idString = UserDefaults.standard.string(forKey: Self.lastSelectedNoteIDKey),
              let id = UUID(uuidString: idString),
              notesVM.note(for: id) != nil else { return }
        notesVM.selectedNoteID = id
    }

    private func startFolderMonitor(url: URL) {
        let monitor = IOSFolderMonitor(folderURL: url) { statuses, changedPaths in
            notesVM.updateSyncStatuses(statuses)
            Task { await notesVM.reconcileFilesystem(changedPaths: changedPaths) }
        }
        monitor.start()
        folderMonitor = monitor
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            folderMonitor?.stop()
            let taskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            Task {
                await notesVM.flushBeforeQuit()
                UIApplication.shared.endBackgroundTask(taskID)
            }
        case .active:
            if let url = notesVM.notesFolderURL {
                if folderMonitor == nil {
                    startFolderMonitor(url: url)
                } else {
                    folderMonitor?.start()
                }
            }
            if hasSeenFirstActiveTransition {
                Task { await notesVM.reconcileFilesystem() }
            } else {
                hasSeenFirstActiveTransition = true
            }
        @unknown default:
            break
        }
    }
}
