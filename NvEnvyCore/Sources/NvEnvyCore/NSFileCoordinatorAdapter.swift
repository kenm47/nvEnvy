import Foundation

/// `FileAccessCoordinator` implementation backed by `NSFileCoordinator`, for
/// iCloud-safe reads/writes to a folder the user granted access to via
/// `UIDocumentPickerViewController`. iOS-only consumer — macOS keeps using
/// `PassthroughFileAccessCoordinator` to preserve its direct-I/O read
/// performance.
public struct NSFileCoordinatorAdapter: FileAccessCoordinator {
    public init() {}

    public func coordinate<T>(readingItemAt url: URL, _ work: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: .withoutChanges, error: &coordinatorError
        ) { newURL in
            result = Result { try work(newURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result!.get()
    }

    public func coordinate<T>(writingItemAt url: URL, _ work: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinatorError
        ) { newURL in
            result = Result { try work(newURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result!.get()
    }
}
