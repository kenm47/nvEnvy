import OSLog

/// Shared signposter for `Instruments` (Points of Interest / os_signpost)
/// instrumentation of launch, parse, reconciliation, and search. No behavior
/// change; overhead when not recording is negligible.
public enum PerformanceTelemetry {
    public static let logger = Logger(subsystem: "com.nvenvy.app", category: "Performance")
    public static let signposter = OSSignposter(logger: logger)

    /// Times `work`, emitting both a signpost interval (for Instruments) and an
    /// `info` log line carrying the duration.
    ///
    /// The log line is the point: a signpost alone needs Instruments attached and a
    /// deliberate recording session, which means nobody looks. A phase breakdown of a
    /// real launch on a real vault is obtainable from a terminal with
    ///
    ///     log stream --predicate 'subsystem == "com.nvenvy.app" AND category == "Performance"'
    ///
    /// A single overly coarse interval around all of `readAllNotes` is what let a
    /// ~300x enumeration regression sit unnoticed; phases need to be narrow enough
    /// that a number points at a line.
    public static func phase<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            signposter.endInterval(name, state)
            logger.info("phase \(name, privacy: .public) \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        }
        return try work()
    }

    /// `async` counterpart to ``phase(_:_:)``.
    public static func phaseAsync<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            signposter.endInterval(name, state)
            logger.info("phase \(name, privacy: .public) \(ms, format: .fixed(precision: 1), privacy: .public) ms")
        }
        return try await work()
    }
}
