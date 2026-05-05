import Foundation

#if os(macOS)
public final class FileSystemMonitor: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable () -> Void
    private let queue: DispatchQueue

    public init(directory: URL, callback: @escaping @Sendable () -> Void) {
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
    let callback: @Sendable () -> Void
    init(_ callback: @escaping @Sendable () -> Void) {
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
    wrapper.callback()
}
#endif
