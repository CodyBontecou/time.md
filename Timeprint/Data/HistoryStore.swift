import Foundation
import SQLite3

/// Persistent local store that accumulates Screen Time data from the system's
/// knowledgeC.db, preserving history beyond Apple's ~7-day retention window.
///
/// Data is stored in a normalized `usage` table at
/// `~/Library/Application Support/Timeprint/screentime.db`.
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
            .appendingPathComponent("Library/Application Support/Timeprint", isDirectory: true)
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
    static func forceSync() {
        syncLock.lock()
        defer { syncLock.unlock() }

        do {
            try performSync()
            _lastSyncDate = Date()
        } catch {
            print("[HistoryStore] Force sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync implementation

    private static func performSync() throws {
        // Locate the system knowledgeC.db
        let knowledgePath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
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
            source_timestamp REAL
        );
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }

        // Migration: add source_timestamp if the table predates this column.
        // ALTER TABLE ADD COLUMN errors when the column already exists — that's fine.
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN source_timestamp REAL", nil, nil, nil)

        // Indexes (idempotent).
        let indexSQL = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_dedup ON usage(app_name, source_timestamp);
        CREATE INDEX IF NOT EXISTS idx_usage_start_time ON usage(start_time);
        CREATE INDEX IF NOT EXISTS idx_usage_app_name ON usage(app_name);
        CREATE INDEX IF NOT EXISTS idx_usage_stream_type ON usage(stream_type);
        """
        guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Read from knowledgeC.db

    private struct UsageRow {
        let appName: String
        let startTime: String       // ISO-8601 local datetime
        let durationSeconds: Double
        let sourceTimestamp: Double  // Original Apple-epoch timestamp (for dedup)
    }

    private static func readKnowledgeRows(from db: OpaquePointer) -> [UsageRow] {
        let sql = """
        SELECT
            ZVALUESTRING,
            ZSTARTDATE,
            CASE WHEN ZENDDATE > ZSTARTDATE THEN (ZENDDATE - ZSTARTDATE) ELSE 0 END
        FROM ZOBJECT
        WHERE ZSTREAMNAME = '/app/usage'
          AND ZVALUESTRING IS NOT NULL
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

            let date = Date(timeIntervalSince1970: appleTimestamp + appleEpochOffset)
            let iso = formatter.string(from: date)

            rows.append(UsageRow(
                appName: appName,
                startTime: iso,
                durationSeconds: duration,
                sourceTimestamp: appleTimestamp
            ))
        }

        return rows
    }

    // MARK: - Write to history.db

    private static func insertRows(_ rows: [UsageRow], into db: OpaquePointer, path: String) throws {
        let sql = """
        INSERT OR IGNORE INTO usage (app_name, duration_seconds, start_time, stream_type, source_timestamp)
        VALUES (?, ?, ?, 'app_usage', ?)
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
            sqlite3_bind_double(statement, 4, row.sourceTimestamp)

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
