import Foundation
import NvEnvyCore

/// iOS has no FSEvents equivalent for a folder granted through
/// `UIDocumentPickerViewController`. This watches the notes folder via
/// `NSMetadataQuery` (external-documents scope, the API meant for
/// picker-granted iCloud folders) so external edits — from the Mac, from
/// Files, from another device — are picked up while the app is active.
///
/// Mirrors the delta-processing shape of the macOS `ICloudStatusMonitor`
/// (`nvEnvy/nvEnvy/ICloudStatusMonitor.swift`) — same "only touch NSFileVersion
/// when a conflict flag is set" perf discipline — but also forwards raw
/// changed paths so the caller can drive `NotesViewModel.reconcileFilesystem`.
@MainActor
final class IOSFolderMonitor {
    private let query = NSMetadataQuery()
    private let folderURL: URL
    private let onChanges: (_ statuses: [String: SyncStatus], _ changedPaths: [String]) -> Void
    private var isRunning = false

    init(folderURL: URL, onChanges: @escaping (_ statuses: [String: SyncStatus], _ changedPaths: [String]) -> Void) {
        self.folderURL = folderURL
        self.onChanges = onChanges
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        query.searchScopes = [NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, folderURL.path)
        query.valueListAttributes = [
            NSMetadataUbiquitousItemDownloadingStatusKey,
            NSMetadataUbiquitousItemIsUploadingKey,
            NSMetadataUbiquitousItemIsDownloadingKey,
            NSMetadataUbiquitousItemHasUnresolvedConflictsKey,
        ]

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate, object: query
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: query
        )

        query.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let items: [NSMetadataItem]
        if notification.name == .NSMetadataQueryDidFinishGathering {
            items = (0..<query.resultCount).compactMap { query.result(at: $0) as? NSMetadataItem }
        } else {
            let userInfo = notification.userInfo
            let changed = userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? []
            let added = userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            items = changed + added
        }
        guard !items.isEmpty else { return }

        var statuses: [String: SyncStatus] = [:]
        var changedPaths: [String] = []

        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            changedPaths.append(path)

            let filename = url.deletingPathExtension().lastPathComponent
            statuses[filename] = syncStatus(for: item, at: url)

            // Files not yet downloaded (`.icloud` placeholders) never appear in
            // reconcile results until pulled locally — kick off the download so
            // the note surfaces automatically once it lands.
            let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }

        onChanges(statuses, changedPaths)
    }

    private func syncStatus(for item: NSMetadataItem, at url: URL) -> SyncStatus {
        let hasConflicts = item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool ?? false
        if hasConflicts,
           let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
           !conflicts.isEmpty {
            return .conflict
        }

        guard let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
              let isUploading = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool,
              let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool else {
            return .local
        }

        if isUploading { return .uploading }
        if isDownloading { return .downloading }
        if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent { return .current }
        return .local
    }
}
