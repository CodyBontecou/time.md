import Foundation
import SQLite3

/// Deletes raw input events older than the user-configured retention window.
/// Aggregates (`typed_words`, `cursor_heatmap_bins`) are preserved indefinitely
/// — they're cheap and what powers the dashboard charts.
///
/// Defaults: raw mouse 7 days, raw keystrokes 14 days. Configurable via
/// `inputTrackingRawRetentionDays`. Runs at app launch and every 6 hours.
final class InputDataPruner: @unchecked Sendable {

    static let shared = InputDataPruner()

    static let retentionDaysKey = "inputTrackingRawRetentionDays"
    static let defaultRetentionDays: Int = 14
    private static let runIntervalSeconds: TimeInterval = 6 * 60 * 60
    private static let vacuumIntervalSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let lastVacuumKey = "input_pruner_last_vacuum_ts"

    private var timer: DispatchSourceTimer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        // Run once immediately so a launch after a long gap reclaims space.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.pruneNow()
        }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + Self.runIntervalSeconds, repeating: Self.runIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.pruneNow()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func pruneNow() {
        let retentionDays = max(1, UserDefaults.standard.integer(forKey: Self.retentionDaysKey).nonZero ?? Self.defaultRetentionDays)
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970

        do {
            let dbURL = try HistoryStore.inputTrackingDatabaseURL()
            var handle: OpaquePointer?
            guard sqlite3_open_v2(
                dbURL.path, &handle,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
            ) == SQLITE_OK, let db = handle else {
                if let handle { sqlite3_close(handle) }
                return
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 5000)

            // Mouse events get a tighter retention because they grow faster.
            let mouseRetentionDays = max(1, retentionDays / 2)
            let mouseCutoff = Date().addingTimeInterval(-Double(mouseRetentionDays) * 86_400).timeIntervalSince1970

            executeDelete(db: db, table: "keystroke_events", cutoff: cutoff)
            executeDelete(db: db, table: "mouse_events", cutoff: mouseCutoff)

            maybeVacuum(db: db)
        } catch {
            NSLog("[InputDataPruner] pruneNow failed: \(error.localizedDescription)")
        }
    }

    private func executeDelete(db: OpaquePointer, table: String, cutoff: Double) {
        let sql = "DELETE FROM \(table) WHERE ts < ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff)
        sqlite3_step(statement)
    }

    private func maybeVacuum(db: OpaquePointer) {
        let now = Date().timeIntervalSince1970
        let last = readMetaDouble(db: db, key: Self.lastVacuumKey) ?? 0
        guard now - last >= Self.vacuumIntervalSeconds else { return }
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
        writeMetaDouble(db: db, key: Self.lastVacuumKey, value: now)
    }

    private func readMetaDouble(db: OpaquePointer, key: String) -> Double? {
        let sql = "SELECT value FROM input_tracking_meta WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return Double(String(cString: cString))
    }

    private func writeMetaDouble(db: OpaquePointer, key: String, value: Double) {
        let sql = """
        INSERT INTO input_tracking_meta (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, "\(value)", -1, transient)
        sqlite3_step(statement)
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
