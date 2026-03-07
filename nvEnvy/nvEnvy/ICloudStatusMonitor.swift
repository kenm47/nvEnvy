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

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }

            let url = URL(fileURLWithPath: path)
            let filename = url.deletingPathExtension().lastPathComponent
            let status = syncStatus(for: item, at: url)

            Task { @MainActor in
                appState?.updateSyncStatus(filename: filename, status: status)
            }
        }
    }

    private func syncStatus(for item: NSMetadataItem, at url: URL) -> SyncStatus {
        // Check for conflicts first
        if let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
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
