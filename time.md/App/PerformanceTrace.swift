import Foundation
import os

/// Lightweight opt-in tracing for launch and data-load performance.
///
/// Enable with `TIMEMD_PERF_TRACE=1` (or the `timemdPerformanceTrace` user
/// default) to print `[PerfTrace]` lines to stderr and unified logging. The
/// checks are intentionally cheap when disabled so this can stay compiled in.
nonisolated enum PerformanceTrace {
    private static let logger = Logger(subsystem: "com.bontecou.time.md", category: "Performance")
    private static let userDefaultsKey = "timemdPerformanceTrace"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TIMEMD_PERF_TRACE"] == "1"
            || UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    @discardableResult
    static func begin(_ label: String, metadata: String? = nil) -> CFAbsoluteTime {
        let start = CFAbsoluteTimeGetCurrent()
        guard isEnabled else { return start }
        event("BEGIN \(label)\(suffix(metadata))")
        return start
    }

    static func end(_ label: String, startedAt start: CFAbsoluteTime, metadata: String? = nil) {
        guard isEnabled else { return }
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        event(String(format: "END %@ %.1fms%@", label, elapsedMS, suffix(metadata)))
    }

    static func event(_ message: String) {
        guard isEnabled else { return }
        logger.notice("\(message, privacy: .public)")
        let line = "[PerfTrace] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private static func suffix(_ metadata: String?) -> String {
        guard let metadata, !metadata.isEmpty else { return "" }
        return " \(metadata)"
    }
}
