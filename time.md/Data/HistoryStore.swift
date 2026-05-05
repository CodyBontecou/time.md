import Foundation
import SQLite3

/// Persistent local store for screen time data recorded by ActiveAppTracker.
///
/// Data is stored in a normalized `usage` table at
/// `~/Library/Application Support/time.md/screentime.db`.
///
/// Opt-in input tracking (keystrokes, cursor) lives in a sibling file
/// `input-tracking.db` so its high-volume mouse_events table never bloats the
/// main DB or slows down the temp-copy used by dashboard queries.
enum HistoryStore {

    // MARK: - Public

    /// Location of the persistent history database.
    /// Creates the file and schema on first call if needed.
    static func databaseURL() throws -> URL {
        let base = try applicationSupportDirectory()
        let url = base.appendingPathComponent("screentime.db")
        try ensureSchema(at: url)
        return url
    }

    /// Location of the input-tracking database (keystrokes, mouse, aggregates).
    /// Separate from `screentime.db` so the high-volume mouse_events table doesn't
    /// pessimize unrelated dashboard / menu-bar queries that copy the main file.
    static func inputTrackingDatabaseURL() throws -> URL {
        let base = try applicationSupportDirectory()
        let url = base.appendingPathComponent("input-tracking.db")
        try ensureInputTrackingSchema(at: url)
        try migrateInputTrackingFromMainDBIfNeeded(newURL: url, baseDirectory: base)
        return url
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/time.md", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
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

    // MARK: - Input tracking schema + migration

    /// Tables backing the opt-in input tracker (keystrokes, mouse events, and
    /// derived aggregates). Lives in `input-tracking.db` so the high-volume
    /// mouse_events table doesn't bloat the main DB.
    private static func ensureInputTrackingSchema(at url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard result == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw ScreenTimeDataError.sqlite(path: url.path, message: "Failed to open input-tracking database")
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_busy_timeout(db, 5000)

        let createSQL = """
        CREATE TABLE IF NOT EXISTS keystroke_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            bundle_id TEXT,
            app_name TEXT,
            key_code INTEGER NOT NULL,
            modifiers INTEGER NOT NULL DEFAULT 0,
            char TEXT,
            is_word_boundary INTEGER NOT NULL DEFAULT 0,
            secure_input INTEGER NOT NULL DEFAULT 0,
            device_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_kev_ts ON keystroke_events(ts);
        CREATE INDEX IF NOT EXISTS idx_kev_bundle_ts ON keystroke_events(bundle_id, ts);

        CREATE TABLE IF NOT EXISTS mouse_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            bundle_id TEXT,
            app_name TEXT,
            kind INTEGER NOT NULL,
            button INTEGER NOT NULL DEFAULT 0,
            x REAL NOT NULL,
            y REAL NOT NULL,
            screen_id INTEGER NOT NULL DEFAULT 0,
            scroll_dx REAL,
            scroll_dy REAL,
            device_id TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_mev_ts ON mouse_events(ts);
        CREATE INDEX IF NOT EXISTS idx_mev_screen_ts ON mouse_events(screen_id, ts);

        CREATE TABLE IF NOT EXISTS typed_words (
            word TEXT NOT NULL,
            bundle_id TEXT NOT NULL DEFAULT '',
            hour_bucket TEXT NOT NULL,
            count INTEGER NOT NULL,
            PRIMARY KEY (word, bundle_id, hour_bucket)
        );
        CREATE INDEX IF NOT EXISTS idx_words_hour ON typed_words(hour_bucket);
        CREATE INDEX IF NOT EXISTS idx_words_count ON typed_words(count);

        CREATE TABLE IF NOT EXISTS cursor_heatmap_bins (
            hour_bucket TEXT NOT NULL,
            bundle_id TEXT NOT NULL DEFAULT '',
            screen_id INTEGER NOT NULL,
            bin_x INTEGER NOT NULL,
            bin_y INTEGER NOT NULL,
            samples INTEGER NOT NULL,
            PRIMARY KEY (hour_bucket, bundle_id, screen_id, bin_x, bin_y)
        );
        CREATE INDEX IF NOT EXISTS idx_heatmap_hour ON cursor_heatmap_bins(hour_bucket);

        CREATE TABLE IF NOT EXISTS input_tracking_meta (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE TABLE IF NOT EXISTS input_consent_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            app_version TEXT NOT NULL,
            action TEXT NOT NULL,
            scope TEXT
        );
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: url.path, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// One-shot migration: copy any input-tracking rows that still live in
    /// `screentime.db` into `input-tracking.db`, then drop the legacy tables
    /// from the main file so subsequent `sqlite3_backup` copies stay small.
    /// Idempotent — gated by a UserDefaults flag.
    private static let migrationFlagKey = "inputTrackingMigratedToSeparateDB_v1"

    private static func migrateInputTrackingFromMainDBIfNeeded(newURL: URL, baseDirectory: URL) throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlagKey) else { return }

        let oldURL = baseDirectory.appendingPathComponent("screentime.db")
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            newURL.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        ) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            return
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 10_000)

        let attachSQL = "ATTACH DATABASE ? AS legacy"
        var attachStmt: OpaquePointer?
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_prepare_v2(db, attachSQL, -1, &attachStmt, nil) == SQLITE_OK,
              let attach = attachStmt else { return }
        sqlite3_bind_text(attach, 1, oldURL.path, -1, transient)
        let attachResult = sqlite3_step(attach)
        sqlite3_finalize(attach)
        guard attachResult == SQLITE_DONE else { return }
        defer { sqlite3_exec(db, "DETACH DATABASE legacy", nil, nil, nil) }

        // Only proceed if the legacy DB actually has the input tables — fresh
        // installs that never had them shouldn't pay any further cost.
        guard legacyHasTable(db: db, name: "keystroke_events") else {
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        let migrationSQL = """
        BEGIN IMMEDIATE;
        INSERT OR IGNORE INTO main.keystroke_events
            SELECT * FROM legacy.keystroke_events;
        INSERT OR IGNORE INTO main.mouse_events
            SELECT * FROM legacy.mouse_events;
        INSERT OR IGNORE INTO main.typed_words
            SELECT * FROM legacy.typed_words;
        INSERT OR IGNORE INTO main.cursor_heatmap_bins
            SELECT * FROM legacy.cursor_heatmap_bins;
        INSERT OR IGNORE INTO main.input_tracking_meta
            SELECT * FROM legacy.input_tracking_meta;
        INSERT OR IGNORE INTO main.input_consent_log
            SELECT * FROM legacy.input_consent_log;
        DROP TABLE IF EXISTS legacy.keystroke_events;
        DROP TABLE IF EXISTS legacy.mouse_events;
        DROP TABLE IF EXISTS legacy.typed_words;
        DROP TABLE IF EXISTS legacy.cursor_heatmap_bins;
        DROP TABLE IF EXISTS legacy.input_tracking_meta;
        DROP TABLE IF EXISTS legacy.input_consent_log;
        COMMIT;
        """
        var errorPointer: UnsafeMutablePointer<CChar>?
        let execResult = sqlite3_exec(db, migrationSQL, nil, nil, &errorPointer)
        if execResult == SQLITE_OK {
            defaults.set(true, forKey: migrationFlagKey)
            // Reclaim the freed pages from the main DB so the next
            // backup-copy is actually smaller.
            sqlite3_exec(db, "VACUUM legacy", nil, nil, nil)
        } else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            if let errorPointer {
                NSLog("[HistoryStore] input tracking migration failed: \(String(cString: errorPointer))")
                sqlite3_free(errorPointer)
            }
        }
    }

    private static func legacyHasTable(db: OpaquePointer, name: String) -> Bool {
        let sql = "SELECT 1 FROM legacy.sqlite_master WHERE type='table' AND name = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return false }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, name, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
