import Foundation
import SQLite3

/// Background aggregator that turns raw `keystroke_events` into hourly
/// `typed_words` rows and raw `mouse_events` into 32-px `cursor_heatmap_bins`.
/// Runs every 60 s. Uses a `last_*_id` cursor in `input_tracking_meta` so each
/// pass only processes what's new.
///
/// Words are filtered before persistence:
///   - too long (> 24 chars) — usually paste blobs
///   - mixed digits + symbols — looks like a password / token
///   - hex-ish (16+ hex digits) — looks like a hash
///   - high Shannon entropy (> 4 bits/char) — looks like random
final class InputAggregator: @unchecked Sendable {

    static let shared = InputAggregator()

    private static let lastKeystrokeIDKey = "last_aggregated_keystroke_id"
    private static let lastMouseIDKey = "last_aggregated_mouse_id"
    private static let runIntervalSeconds: TimeInterval = 60
    private static let cursorBinSize: Double = 32

    private var timer: DispatchSourceTimer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + Self.runIntervalSeconds, repeating: Self.runIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.runOnce()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Public for tests + manual invocation from the dashboard "Refresh" path.
    func runOnce() {
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

            aggregateWords(db: db)
            aggregateCursor(db: db)
        } catch {
            NSLog("[InputAggregator] runOnce failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Words

    private func aggregateWords(db: OpaquePointer) {
        let lastID = readMetaInt(db: db, key: Self.lastKeystrokeIDKey) ?? 0

        let selectSQL = """
        SELECT id, ts, bundle_id, char, secure_input
        FROM keystroke_events
        WHERE id > ? AND char IS NOT NULL AND secure_input = 0
        ORDER BY id ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK,
              let select = stmt else { return }

        sqlite3_bind_int64(select, 1, lastID)

        var lastSeenID: Int64 = lastID
        var currentWord = ""
        var currentBundle: String = ""
        var currentTimestamp: Double = 0

        let upsertSQL = """
        INSERT INTO typed_words (word, bundle_id, hour_bucket, count) VALUES (?, ?, ?, 1)
        ON CONFLICT(word, bundle_id, hour_bucket) DO UPDATE SET count = count + 1
        """
        var upsertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, upsertSQL, -1, &upsertStmt, nil) == SQLITE_OK,
              let upsert = upsertStmt else {
            sqlite3_finalize(select)
            return
        }

        sqlite3_exec(db, "BEGIN", nil, nil, nil)

        while sqlite3_step(select) == SQLITE_ROW {
            let id = sqlite3_column_int64(select, 0)
            let ts = sqlite3_column_double(select, 1)
            let bundleID = Self.columnText(select, index: 2) ?? ""
            let char = Self.columnText(select, index: 3) ?? ""

            lastSeenID = id

            if Self.isBoundary(char) {
                Self.commitWord(currentWord, bundle: currentBundle, ts: currentTimestamp, upsert: upsert)
                currentWord = ""
                continue
            }

            if currentWord.isEmpty {
                currentBundle = bundleID
                currentTimestamp = ts
            }
            currentWord.append(char)

            // Cap word length to bound memory if user pastes a giant blob.
            if currentWord.count > 64 {
                currentWord = ""
            }
        }
        // Flush trailing partial word so it counts on next run if completed.
        // But only if we hit a boundary; otherwise leave it for the next pass.
        Self.commitWord(currentWord, bundle: currentBundle, ts: currentTimestamp, upsert: upsert)

        sqlite3_finalize(select)
        sqlite3_finalize(upsert)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        if lastSeenID > lastID {
            writeMetaInt(db: db, key: Self.lastKeystrokeIDKey, value: lastSeenID)
        }
    }

    private static func commitWord(_ word: String, bundle: String, ts: Double, upsert: OpaquePointer) {
        guard let normalized = normalizeWord(word) else { return }
        let bucket = hourBucket(for: ts)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_reset(upsert)
        sqlite3_bind_text(upsert, 1, normalized, -1, transient)
        sqlite3_bind_text(upsert, 2, bundle, -1, transient)
        sqlite3_bind_text(upsert, 3, bucket, -1, transient)
        sqlite3_step(upsert)
    }

    /// Returns the normalized word, or nil if it should be filtered.
    static func normalizeWord(_ raw: String) -> String? {
        let lower = raw.lowercased()
            .precomposedStringWithCanonicalMapping
        guard !lower.isEmpty else { return nil }
        guard lower.count >= 2 else { return nil }
        guard lower.count <= 24 else { return nil }

        // All characters must be letters or hyphens/apostrophes (no digits, no symbols).
        // Words with digits or unusual symbols often look like passwords / tokens.
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "'-_"))
        guard lower.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        // Strip leading/trailing punctuation/whitespace.
        let trimmed = lower.trimmingCharacters(in: CharacterSet(charactersIn: "'-_"))
        guard trimmed.count >= 2 else { return nil }

        // Reject hex-shaped strings.
        if trimmed.count >= 16,
           trimmed.allSatisfy({ "0123456789abcdef".contains($0) }) {
            return nil
        }

        // Reject high-entropy strings (looks like random output).
        if shannonEntropy(trimmed) > 4.0 {
            return nil
        }

        return trimmed
    }

    private static func shannonEntropy(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        var freq: [Character: Int] = [:]
        for c in s { freq[c, default: 0] += 1 }
        let n = Double(s.count)
        var h = 0.0
        for count in freq.values {
            let p = Double(count) / n
            h -= p * (log(p) / log(2.0))
        }
        return h
    }

    private static func isBoundary(_ char: String) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return true }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        if CharacterSet.punctuationCharacters.contains(scalar) { return true }
        if scalar.value < 32 { return true }
        return false
    }

    // MARK: - Cursor heatmap

    private func aggregateCursor(db: OpaquePointer) {
        let lastID = readMetaInt(db: db, key: Self.lastMouseIDKey) ?? 0

        // Aggregate move + drag events into 32-px bins, hourly. Skip clicks /
        // scrolls — those bias the heatmap toward the few pixels under the
        // user's hand at click time and aren't really representative of where
        // the cursor *is*.
        let selectSQL = """
        SELECT id, ts, bundle_id, screen_id, x, y
        FROM mouse_events
        WHERE id > ? AND kind IN (0, 4)
        ORDER BY id ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK,
              let select = stmt else { return }

        sqlite3_bind_int64(select, 1, lastID)

        let upsertSQL = """
        INSERT INTO cursor_heatmap_bins (hour_bucket, bundle_id, screen_id, bin_x, bin_y, samples)
        VALUES (?, ?, ?, ?, ?, 1)
        ON CONFLICT(hour_bucket, bundle_id, screen_id, bin_x, bin_y)
        DO UPDATE SET samples = samples + 1
        """
        var upsertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, upsertSQL, -1, &upsertStmt, nil) == SQLITE_OK,
              let upsert = upsertStmt else {
            sqlite3_finalize(select)
            return
        }

        sqlite3_exec(db, "BEGIN", nil, nil, nil)

        var lastSeenID: Int64 = lastID
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        while sqlite3_step(select) == SQLITE_ROW {
            let id = sqlite3_column_int64(select, 0)
            let ts = sqlite3_column_double(select, 1)
            let bundleID = Self.columnText(select, index: 2) ?? ""
            let screenID = sqlite3_column_int64(select, 3)
            let x = sqlite3_column_double(select, 4)
            let y = sqlite3_column_double(select, 5)

            lastSeenID = id

            let binX = Int(floor(x / Self.cursorBinSize))
            let binY = Int(floor(y / Self.cursorBinSize))
            let bucket = Self.hourBucket(for: ts)

            sqlite3_reset(upsert)
            sqlite3_bind_text(upsert, 1, bucket, -1, transient)
            sqlite3_bind_text(upsert, 2, bundleID, -1, transient)
            sqlite3_bind_int64(upsert, 3, screenID)
            sqlite3_bind_int(upsert, 4, Int32(binX))
            sqlite3_bind_int(upsert, 5, Int32(binY))
            sqlite3_step(upsert)
        }

        sqlite3_finalize(select)
        sqlite3_finalize(upsert)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        if lastSeenID > lastID {
            writeMetaInt(db: db, key: Self.lastMouseIDKey, value: lastSeenID)
        }
    }

    // MARK: - Meta helpers

    private func readMetaInt(db: OpaquePointer, key: String) -> Int64? {
        let sql = "SELECT value FROM input_tracking_meta WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return Int64(String(cString: cString))
    }

    private func writeMetaInt(db: OpaquePointer, key: String, value: Int64) {
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

    // MARK: - Misc helpers

    static func hourBucket(for timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:00"
        return formatter.string(from: date)
    }

    private static func columnText(_ stmt: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cString)
    }
}
