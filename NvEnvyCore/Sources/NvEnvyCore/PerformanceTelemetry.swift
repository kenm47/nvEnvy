import OSLog

/// Shared signposter for `Instruments` (Points of Interest / os_signpost)
/// instrumentation of launch, parse, reconciliation, and search. No behavior
/// change; overhead when not recording is negligible.
public enum PerformanceTelemetry {
    public static let logger = Logger(subsystem: "com.nvenvy.app", category: "Performance")
    public static let signposter = OSSignposter(logger: logger)
}
