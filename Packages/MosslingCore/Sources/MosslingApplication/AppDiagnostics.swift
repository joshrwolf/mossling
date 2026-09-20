import Foundation
#if DEBUG && canImport(os)
import os
#endif

/// Local Debug diagnostics only. No document contents, identifiers or payloads
/// are logged, and Release builds compile these calls to no-ops.
public enum AppDiagnostics {
    public struct Interval {
        #if DEBUG && canImport(os)
        let name: StaticString
        let id: OSSignpostID
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
        #endif
    }

    #if DEBUG && canImport(os)
    private static let logger = Logger(subsystem: "com.joshrwolf.mossling", category: "Lifecycle")
    private static let signposter = OSSignposter(logger: logger)
    #endif

    public static func begin(_ name: StaticString) -> Interval {
        #if DEBUG && canImport(os)
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        logger.notice("\(String(describing: name), privacy: .public) begin id=\(id.rawValue)")
        return Interval(name: name, id: id, state: state, start: .now)
        #else
        return Interval()
        #endif
    }

    public static func end(_ interval: Interval) {
        #if DEBUG && canImport(os)
        let duration = interval.start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        signposter.endInterval(interval.name, interval.state)
        logger.notice("\(String(describing: interval.name), privacy: .public) end id=\(interval.id.rawValue) duration_ms=\(milliseconds)")
        #endif
    }

    public static func event(_ name: StaticString) {
        #if DEBUG && canImport(os)
        signposter.emitEvent(name)
        logger.notice("\(String(describing: name), privacy: .public)")
        #endif
    }
}
