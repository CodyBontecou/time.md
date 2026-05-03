import Foundation
import SQLite3

/// Persistent local store for screen time data recorded by ActiveAppTracker.
///
/// Data is stored in a normalized `usage` table at
/// `~/Library/Application Support/time.md/screentime.db`.
enum HistoryStore {

    // MARK: - Public

    /// Location of the persistent history database.
    /// Creates the file and schema on first call if needed.
    static func databaseURL() throws -> URL {
        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/time.md", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("screentime.db")
        try ensureSchema(at: url)
        return url
    }

    // MARK: - Schema

    private static func ensureSchema(at url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard result == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw ScreenTimeDataError.sqlite(path: url.path, message: "Failed to open database")
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_busy_timeout(db, 5000)

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
            throw ScreenTimeDataError.sqlite(path: url.path, message: String(cString: sqlite3_errmsg(db)))
        }

        // Migrations: ADD COLUMN errors when the column already exists — that's fine.
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN source_timestamp REAL", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN device_id TEXT", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN metadata_hash TEXT", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN url TEXT", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE usage ADD COLUMN title TEXT", nil, nil, nil)

        // Indexes (idempotent).
        let indexSQL = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_usage_dedup_v2 ON usage(app_name, source_timestamp, stream_type);
        CREATE INDEX IF NOT EXISTS idx_usage_start_time ON usage(start_time);
        CREATE INDEX IF NOT EXISTS idx_usage_app_name ON usage(app_name);
        CREATE INDEX IF NOT EXISTS idx_usage_stream_type ON usage(stream_type);
        CREATE INDEX IF NOT EXISTS idx_usage_device_id ON usage(device_id);
        """
        guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: url.path, message: String(cString: sqlite3_errmsg(db)))
        }

        // Drop the old dedup index that didn't include stream_type.
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_usage_dedup", nil, nil, nil)
    }
}
