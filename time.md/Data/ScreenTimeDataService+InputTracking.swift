import Foundation
import SQLite3

// MARK: - Input tracking queries

/// All queries here read directly from the live `screentime.db` (no temp-copy
/// path) because the input tables can be huge (mouse events) and copying them
/// per-query would be too slow. `validateNormalizedSchema` only requires the
/// `usage` table, so this won't conflict with the rest of the service.
extension SQLiteScreenTimeDataService {

    func fetchCursorHeatmap(
        startDate: Date,
        endDate: Date,
        screenID: Int?,
        bundleID: String?
    ) async throws -> [CursorHeatmapBin] {
        try await runOnInputDB { db in
            let startBucket = Self.hourBucketString(from: startDate)
            let endBucket = Self.hourBucketString(from: endDate)

            var sql = """
            SELECT screen_id, bin_x, bin_y, SUM(samples) AS total
            FROM cursor_heatmap_bins
            WHERE hour_bucket >= ? AND hour_bucket <= ?
            """
            var bindings: [(Int32, (OpaquePointer?) -> Void)] = []
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            bindings.append((1, { stmt in sqlite3_bind_text(stmt, 1, startBucket, -1, transient) }))
            bindings.append((2, { stmt in sqlite3_bind_text(stmt, 2, endBucket, -1, transient) }))

            var nextIdx: Int32 = 3
            if let screenID {
                sql += " AND screen_id = ?"
                let idx = nextIdx
                bindings.append((idx, { stmt in sqlite3_bind_int64(stmt, idx, Int64(screenID)) }))
                nextIdx += 1
            }
            if let bundleID, !bundleID.isEmpty {
                sql += " AND bundle_id = ?"
                let idx = nextIdx
                bindings.append((idx, { stmt in sqlite3_bind_text(stmt, idx, bundleID, -1, transient) }))
                nextIdx += 1
            }
            sql += " GROUP BY screen_id, bin_x, bin_y"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            for (_, bind) in bindings { bind(statement) }

            var results: [CursorHeatmapBin] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let screen = Int(sqlite3_column_int64(statement, 0))
                let x = Int(sqlite3_column_int64(statement, 1))
                let y = Int(sqlite3_column_int64(statement, 2))
                let total = Int(sqlite3_column_int64(statement, 3))
                results.append(CursorHeatmapBin(screenID: screen, binX: x, binY: y, samples: total))
            }
            return results
        }
    }

    func fetchTopTypedWords(
        startDate: Date,
        endDate: Date,
        bundleID: String?,
        limit: Int
    ) async throws -> [TypedWordRow] {
        try await runOnInputDB { db in
            let startBucket = Self.hourBucketString(from: startDate)
            let endBucket = Self.hourBucketString(from: endDate)

            var sql = """
            SELECT word, SUM(count) AS total
            FROM typed_words
            WHERE hour_bucket >= ? AND hour_bucket <= ?
            """
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            if let bundleID, !bundleID.isEmpty {
                sql += " AND bundle_id = ?"
            }
            sql += " GROUP BY word ORDER BY total DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, startBucket, -1, transient)
            sqlite3_bind_text(statement, 2, endBucket, -1, transient)
            var nextIdx: Int32 = 3
            if let bundleID, !bundleID.isEmpty {
                sqlite3_bind_text(statement, nextIdx, bundleID, -1, transient)
                nextIdx += 1
            }
            sqlite3_bind_int64(statement, nextIdx, Int64(limit))

            var results: [TypedWordRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(statement, 0) else { continue }
                let word = String(cString: cString)
                let total = Int(sqlite3_column_int64(statement, 1))
                results.append(TypedWordRow(word: word, count: total))
            }
            return results
        }
    }

    func fetchTopTypedKeys(
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [TypedKeyRow] {
        try await runOnInputDB { db in
            let sql = """
            SELECT key_code, COUNT(*) AS count
            FROM keystroke_events
            WHERE ts >= ? AND ts <= ?
            GROUP BY key_code
            ORDER BY count DESC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 3, Int64(limit))

            var results: [TypedKeyRow] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let code = Int(sqlite3_column_int64(statement, 0))
                let count = Int(sqlite3_column_int64(statement, 1))
                results.append(TypedKeyRow(keyCode: code, label: KeyCodeLabels.label(for: code), count: count))
            }
            return results
        }
    }

    func fetchTypingIntensity(
        startDate: Date,
        endDate: Date,
        granularity: IntensityGranularity
    ) async throws -> [IntensityPoint] {
        try await runOnInputDB { db in
            // SQLite's strftime works on text dates; we have unix epoch.
            // datetime(ts, 'unixepoch', 'localtime') converts.
            let bucketExpr: String
            switch granularity {
            case .minute:
                bucketExpr = "strftime('%Y-%m-%d %H:%M:00', datetime(ts, 'unixepoch', 'localtime'))"
            case .hour:
                bucketExpr = "strftime('%Y-%m-%d %H:00:00', datetime(ts, 'unixepoch', 'localtime'))"
            }

            let sql = """
            SELECT \(bucketExpr) AS bucket, COUNT(*) AS count
            FROM keystroke_events
            WHERE ts >= ? AND ts <= ?
            GROUP BY bucket
            ORDER BY bucket
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            var results: [IntensityPoint] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(statement, 0) else { continue }
                let bucket = String(cString: cString)
                let count = Int(sqlite3_column_int64(statement, 1))
                guard let date = formatter.date(from: bucket) else { continue }
                results.append(IntensityPoint(date: date, count: count))
            }
            return results
        }
    }

    func fetchInputTrackingScreenIDs(
        startDate: Date,
        endDate: Date
    ) async throws -> [Int] {
        try await runOnInputDB { db in
            let sql = """
            SELECT DISTINCT screen_id
            FROM mouse_events
            WHERE ts >= ? AND ts <= ?
            ORDER BY screen_id
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)

            var results: [Int] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(Int(sqlite3_column_int64(statement, 0)))
            }
            return results
        }
    }

    func fetchInputTrackingBundleIDs(
        startDate: Date,
        endDate: Date
    ) async throws -> [String] {
        try await runOnInputDB { db in
            let sql = """
            SELECT bundle_id, COUNT(*) AS cnt
            FROM mouse_events
            WHERE ts >= ? AND ts <= ? AND bundle_id IS NOT NULL AND bundle_id != ''
            GROUP BY bundle_id
            ORDER BY cnt DESC
            LIMIT 50
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)

            var results: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(statement, 0) else { continue }
                results.append(String(cString: cString))
            }
            return results
        }
    }

    func fetchRawKeystrokeEvents(
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [RawKeystrokeEvent] {
        try await runOnInputDB { db in
            let sql = """
            SELECT ts, bundle_id, app_name, key_code, modifiers, char, is_word_boundary, secure_input
            FROM keystroke_events
            WHERE ts >= ? AND ts <= ?
            ORDER BY ts ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 3, Int64(limit))

            var results: [RawKeystrokeEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let ts = sqlite3_column_double(statement, 0)
                let bundleID = Self.columnText(statement, index: 1)
                let appName = Self.columnText(statement, index: 2)
                let keyCode = Int(sqlite3_column_int64(statement, 3))
                let modifiers = sqlite3_column_int64(statement, 4)
                let char = Self.columnText(statement, index: 5)
                let isBoundary = sqlite3_column_int64(statement, 6) != 0
                let secureInput = sqlite3_column_int64(statement, 7) != 0
                results.append(RawKeystrokeEvent(
                    timestamp: Date(timeIntervalSince1970: ts),
                    bundleID: bundleID,
                    appName: appName,
                    keyCode: keyCode,
                    modifiers: modifiers,
                    char: char,
                    isWordBoundary: isBoundary,
                    secureInput: secureInput
                ))
            }
            return results
        }
    }

    func fetchRawKeystrokeEventCount(
        startDate: Date,
        endDate: Date
    ) async throws -> Int {
        try await runOnInputDB { db in
            try Self.scalarCount(
                db: db,
                sql: "SELECT COUNT(*) FROM keystroke_events WHERE ts >= ? AND ts <= ?",
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    func fetchRawMouseEvents(
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [RawMouseEvent] {
        try await runOnInputDB { db in
            let sql = """
            SELECT ts, bundle_id, app_name, kind, button, x, y, screen_id, scroll_dx, scroll_dy
            FROM mouse_events
            WHERE ts >= ? AND ts <= ?
            ORDER BY ts ASC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 3, Int64(limit))

            var results: [RawMouseEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let ts = sqlite3_column_double(statement, 0)
                let bundleID = Self.columnText(statement, index: 1)
                let appName = Self.columnText(statement, index: 2)
                let kind = Int(sqlite3_column_int64(statement, 3))
                let button = Int(sqlite3_column_int64(statement, 4))
                let x = sqlite3_column_double(statement, 5)
                let y = sqlite3_column_double(statement, 6)
                let screenID = Int(sqlite3_column_int64(statement, 7))
                let dx = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 8)
                let dy = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 9)
                results.append(RawMouseEvent(
                    timestamp: Date(timeIntervalSince1970: ts),
                    bundleID: bundleID,
                    appName: appName,
                    kind: kind,
                    button: button,
                    x: x,
                    y: y,
                    screenID: screenID,
                    scrollDX: dx,
                    scrollDY: dy
                ))
            }
            return results
        }
    }

    func fetchRawMouseEventCount(
        startDate: Date,
        endDate: Date
    ) async throws -> Int {
        try await runOnInputDB { db in
            try Self.scalarCount(
                db: db,
                sql: "SELECT COUNT(*) FROM mouse_events WHERE ts >= ? AND ts <= ?",
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    private static func scalarCount(db: OpaquePointer, sql: String, startDate: Date, endDate: Date) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func columnText(_ stmt: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cString)
    }

    func fetchClickLocations(
        startDate: Date,
        endDate: Date,
        screenID: Int?,
        bundleID: String?,
        limit: Int
    ) async throws -> [ClickLocation] {
        try await runOnInputDB { db in
            var sql = """
            SELECT x, y, screen_id
            FROM mouse_events
            WHERE ts >= ? AND ts <= ? AND kind = 1
            """
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            if screenID != nil {
                sql += " AND screen_id = ?"
            }
            if bundleID != nil {
                sql += " AND bundle_id = ?"
            }
            sql += " ORDER BY ts DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                return []
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)
            var idx: Int32 = 3
            if let screenID {
                sqlite3_bind_int64(statement, idx, Int64(screenID))
                idx += 1
            }
            if let bundleID {
                sqlite3_bind_text(statement, idx, bundleID, -1, transient)
                idx += 1
            }
            sqlite3_bind_int64(statement, idx, Int64(limit))

            var results: [ClickLocation] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let x = sqlite3_column_double(statement, 0)
                let y = sqlite3_column_double(statement, 1)
                let sid = Int(sqlite3_column_int64(statement, 2))
                results.append(ClickLocation(x: x, y: y, screenID: sid))
            }
            return results
        }
    }

    // MARK: - Internal helpers

    /// Opens the live `input-tracking.db` read-only and runs the closure on a
    /// background queue. Used for input-tracking queries that need the
    /// freshest data and where copying the (potentially large) DB on every
    /// query would be wasteful.
    private func runOnInputDB<T: Sendable>(
        _ operation: @escaping @Sendable (OpaquePointer) throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            let dbURL = try HistoryStore.inputTrackingDatabaseURL()
            var handle: OpaquePointer?
            guard sqlite3_open_v2(
                dbURL.path, &handle,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil
            ) == SQLITE_OK, let db = handle else {
                if let handle { sqlite3_close(handle) }
                throw ScreenTimeDataError.sqlite(path: dbURL.path, message: "Failed to open input DB")
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 5000)
            return try operation(db)
        }.value
    }

    private static func hourBucketString(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:00"
        return f.string(from: date)
    }
}

// MARK: - Key code labels

enum KeyCodeLabels {
    /// Subset of macOS virtual key codes — covers the keys users actually press
    /// most often. Anything not listed falls back to "Key (code)".
    private static let table: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Escape",
        55: "Cmd", 56: "Shift", 57: "Caps Lock", 58: "Option", 59: "Control",
        60: "Right Shift", 61: "Right Option", 62: "Right Control",
        63: "Function",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow"
    ]

    static func label(for keyCode: Int) -> String {
        table[keyCode] ?? "Key \(keyCode)"
    }
}
