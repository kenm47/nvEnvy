import Foundation
import NvEnvyCore

@MainActor
final class ICloudStatusMonitor {
    private var metadataQuery: NSMetadataQuery?
    private weak var appState: AppState?
    private let notesDirectory: URL

    init(notesDirectory: URL, appState: AppState) {
        self.notesDirectory = notesDirectory
        self.appState = appState
    }

    func start() {
        let query = NSMetadataQuery()
        query.searchScopes = [notesDirectory]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        query.start()
        self.metadataQuery = query
    }

    func stop() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        guard let query = metadataQuery else { return }

        query.disableUpdates()
        defer { query.enableUpdates() }

        // Only the initial gather needs every result. Subsequent updates carry
        // the delta in userInfo — processing just that avoids an O(N) scan (and
        // an NSFileVersion/status computation per file) on every metadata tick.
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

        var batch: [String: SyncStatus] = [:]
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let filename = url.deletingPathExtension().lastPathComponent
            batch[filename] = syncStatus(for: item, at: url)
        }
        guard !batch.isEmpty else { return }

        // One MainActor hop (and one NoteStore call) for the whole batch,
        // instead of one Task per changed file.
        Task { @MainActor [weak appState] in
            appState?.updateSyncStatuses(batch)
        }
    }

    private func syncStatus(for item: NSMetadataItem, at url: URL) -> SyncStatus {
        // `NSFileVersion.unresolvedConflictVersionsOfItem` is a syscall; only
        // pay for it when the item's own metadata flags a conflict.
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

        if isUploading {
            return .uploading
        }
        if isDownloading {
            return .downloading
        }
        if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
            return .current
        }

        return .local
    }
}
