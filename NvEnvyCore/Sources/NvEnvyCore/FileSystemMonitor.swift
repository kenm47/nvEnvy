import Foundation

#if os(macOS)
/// True when any flag in the batch means the incremental path list can't be
/// trusted and a full directory rescan is required (buffer overflow, or FSEvents
/// itself telling us to rescan a subtree).
public func fsEventFlagsRequireFullRescan(_ flags: [FSEventStreamEventFlags]) -> Bool {
    let rescanMask = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount
            | kFSEventStreamEventFlagUnmount
            | kFSEventStreamEventFlagHistoryDone
    )
    return flags.contains { $0 & rescanMask != 0 }
}

public final class FileSystemMonitor: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable ([String], [FSEventStreamEventFlags]) -> Void
    private let queue: DispatchQueue

    public init(directory: URL, callback: @escaping @Sendable ([String], [FSEventStreamEventFlags]) -> Void) {
        self.path = directory.path
        self.callback = callback
        self.queue = DispatchQueue(label: "com.nvenvy.fsmonitor", qos: .utility)
    }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(CallbackWrapper(callback)).toOpaque()

        let pathsToWatch = [path] as CFArray
        stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}

private final class CallbackWrapper {
    let callback: @Sendable ([String], [FSEventStreamEventFlags]) -> Void
    init(_ callback: @escaping @Sendable ([String], [FSEventStreamEventFlags]) -> Void) {
        self.callback = callback
    }
}

private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let wrapper = Unmanaged<CallbackWrapper>.fromOpaque(info).takeUnretainedValue()
    // kFSEventStreamCreateFlagUseCFTypes means eventPaths is a CFArray of CFString.
    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
    let paths = (cfPaths as? [String]) ?? []
    let flags = (0..<numEvents).map { eventFlags[$0] }
    wrapper.callback(paths, flags)
}
#endif
