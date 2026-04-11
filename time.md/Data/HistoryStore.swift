import Foundation
import SQLite3

/// Persistent local store that accumulates Screen Time data from the system's
/// knowledgeC.db, preserving history beyond Apple's ~7-day retention window.
///
/// Data is stored in a normalized `usage` table at
/// `~/Library/Application Support/time.md/screentime.db`.
enum HistoryStore {
    private static let appleEpochOffset: Double = 978_307_200
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let syncLock = NSLock()
    private static var _lastSyncDate: Date?
    private static let syncInterval: TimeInterval = 900 // 15 minutes

    // MARK: - Public

    /// Location of the persistent history database.
    static func databaseURL() throws -> URL {
        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/time.md", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("screentime.db")
    }

    /// Syncs from knowledgeC.db if enough time has elapsed since the last sync.
    /// Thread-safe; concurrent callers are serialized and deduplicated.
    static func syncIfNeeded() {
        syncLock.lock()
        defer { syncLock.unlock() }

        if let last = _lastSyncDate, Date().timeIntervalSince(last) < syncInterval {
            return
        }

        do {
            try performSync()
            _lastSyncDate = Date()
        } catch {
            // Non-fatal: queries still work with whatever data is already in history.db
            print("[HistoryStore] Sync failed: \(error.localizedDescription)")
        }
    }

    /// Force an immediate sync, bypassing the interval throttle.
    /// Used by the background Launch Agent which runs as a separate process.
    /// Returns nil on success, or an error message on failure.
    @discardableResult
    static func forceSync() -> String? {
        syncLock.lock()
        defer { syncLock.unlock() }

        do {
            try performSync()
            _lastSyncDate = Date()
            return nil
        } catch {
            print("[HistoryStore] Force sync failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    // MARK: - Sync implementation

    private static func performSync() throws {
        // Locate the system knowledgeC.db
        let knowledgePath = realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")

        guard FileManager.default.fileExists(atPath: knowledgePath.path) else {
            return // No system DB to sync from
        }

        // Open knowledgeC.db read-only
        var sourceHandle: OpaquePointer?
        let sourceResult = sqlite3_open_v2(
            knowledgePath.path, &sourceHandle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard sourceResult == SQLITE_OK, let sourceDB = sourceHandle else {
            if let sourceHandle { sqlite3_close(sourceHandle) }
            return // Can't open — skip silently
        }
        defer { sqlite3_close(sourceDB) }

        // Verify expected table exists
        guard hasTable(db: sourceDB, name: "ZOBJECT") else { return }

        // Read usage rows
        let rows = readKnowledgeRows(from: sourceDB)
        guard !rows.isEmpty else { return }

        // Open/create the persistent history DB
        let historyURL = try databaseURL()
        var historyHandle: OpaquePointer?
        let historyResult = sqlite3_open_v2(
            historyURL.path, &historyHandle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard historyResult == SQLITE_OK, let historyDB = historyHandle else {
            if let historyHandle { sqlite3_close(historyHandle) }
            throw ScreenTimeDataError.sqlite(
                path: historyURL.path,
                message: "Failed to open history database"
            )
        }
        defer { sqlite3_close(historyDB) }

        // WAL mode for better concurrent-read performance
        sqlite3_exec(historyDB, "PRAGMA journal_mode=WAL", nil, nil, nil)
        
        // Set busy timeout so we wait for locks instead of failing immediately
        sqlite3_busy_timeout(historyDB, 5000) // 5 seconds

        // Ensure schema (with migration support for pre-existing DBs)
        try ensureSchema(db: historyDB, path: historyURL.path)

        // Batch-insert (INSERT OR IGNORE deduplicates via unique index)
        try insertRows(rows, into: historyDB, path: historyURL.path)
    }

    // MARK: - Schema

    private static func ensureSchema(db: OpaquePointer, path: String) throws {
        // Create the table if it doesn't already exist.
        let createSQL = """
        CREATE TABLE IF NOT EXISTS usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            app_name TEXT NOT NULL,
            duration_seconds REAL NOT NULL,
            start_time TEXT NOT NULL,
            stream_type TEXT NOT NULL DEFAULT 'app_usage',
            source_timestamp REAL,
            device_id TEXT,
            metadata_hash TEXT
        );
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }

        // Migrations: ADD COLUMN errors when the column already exists — that's fine.
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN source_timestamp REAL", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN device_id TEXT", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN metadata_hash TEXT", nil, nil, nil)

        // Indexes (idempotent).
        // Dedup key includes stream_type so the same app+timestamp from different
        // streams (e.g. /app/usage vs /app/webUsage) aren't collapsed.
        let indexSQL = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_dedup_v2 ON usage(app_name, source_timestamp, stream_type);
        CREATE INDEX IF NOT EXISTS idx_usage_start_time ON usage(start_time);
        CREATE INDEX IF NOT EXISTS idx_usage_app_name ON usage(app_name);
        CREATE INDEX IF NOT EXISTS idx_usage_stream_type ON usage(stream_type);
        CREATE INDEX IF NOT EXISTS idx_usage_device_id ON usage(device_id);
        """
        guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }

        // Drop the old dedup index that didn't include stream_type.
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_usage_dedup", nil, nil, nil)
    }

    // MARK: - Read from knowledgeC.db

    private struct UsageRow {
        let appName: String
        let startTime: String       // ISO-8601 local datetime
        let durationSeconds: Double
        let sourceTimestamp: Double  // Original Apple-epoch timestamp (for dedup)
        let streamType: String      // e.g. "app_usage", "web_usage", "media_usage"
        let deviceId: String?       // Hardware UUID from ZSOURCE
        let metadataHash: String?   // Hash from ZSTRUCTUREDMETADATA
    }

    /// Maps knowledgeC.db ZSTREAMNAME values to our normalized stream_type keys.
    private static let streamTypeMap: [String: String] = [
        "/app/usage": "app_usage",
        "/app/webUsage": "web_usage",
        "/app/mediaUsage": "media_usage"
    ]

    private static func readKnowledgeRows(from db: OpaquePointer) -> [UsageRow] {
        let sql = """
        SELECT
            o.ZVALUESTRING,
            o.ZSTARTDATE,
            CASE WHEN o.ZENDDATE > o.ZSTARTDATE THEN (o.ZENDDATE - o.ZSTARTDATE) ELSE 0 END,
            o.ZSTREAMNAME,
            s.ZDEVICEID,
            sm.ZMETADATAHASH
        FROM ZOBJECT o
        LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
        LEFT JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
        WHERE o.ZSTREAMNAME IN ('/app/usage', '/app/webUsage', '/app/mediaUsage')
          AND o.ZVALUESTRING IS NOT NULL
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var rows: [UsageRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(statement, 0) else { continue }
            let appName = String(cString: cStr)
            let appleTimestamp = sqlite3_column_double(statement, 1)
            let duration = sqlite3_column_double(statement, 2)

            let rawStream = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "/app/usage"
            let streamType = streamTypeMap[rawStream] ?? "app_usage"

            let deviceId = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            let metadataHash = sqlite3_column_text(statement, 5).map { String(cString: $0) }

            let date = Date(timeIntervalSince1970: appleTimestamp + appleEpochOffset)
            let iso = formatter.string(from: date)

            rows.append(UsageRow(
                appName: appName,
                startTime: iso,
                durationSeconds: duration,
                sourceTimestamp: appleTimestamp,
                streamType: streamType,
                deviceId: deviceId,
                metadataHash: metadataHash
            ))
        }

        return rows
    }

    // MARK: - Write to history.db

    private static func insertRows(_ rows: [UsageRow], into db: OpaquePointer, path: String) throws {
        let sql = """
        INSERT OR IGNORE INTO usage (app_name, duration_seconds, start_time, stream_type, source_timestamp, device_id, metadata_hash)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }

        for row in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            sqlite3_bind_text(statement, 1, row.appName, -1, sqliteTransient)
            sqlite3_bind_double(statement, 2, row.durationSeconds)
            sqlite3_bind_text(statement, 3, row.startTime, -1, sqliteTransient)
            sqlite3_bind_text(statement, 4, row.streamType, -1, sqliteTransient)
            sqlite3_bind_double(statement, 5, row.sourceTimestamp)

            if let deviceId = row.deviceId {
                sqlite3_bind_text(statement, 6, deviceId, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(statement, 6)
            }

            if let metadataHash = row.metadataHash {
                sqlite3_bind_text(statement, 7, metadataHash, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(statement, 7)
            }

            let result = sqlite3_step(statement)
            if result != SQLITE_DONE {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
            }
        }

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Helpers

    private static func hasTable(db: OpaquePointer, name: String) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, name, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
