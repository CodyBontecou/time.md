import Foundation
import SQLite3

/// Persistent local store for screen time data recorded by ActiveAppTracker.
///
/// Data is stored in a normalized `usage` table at
/// `~/Library/Application Support/time.md/screentime.db`.
///
/// Opt-in input tracking (keystrokes, cursor) lives in a sibling file
/// `input-tracking.db` so its high-volume mouse_events table never bloats the
/// main DB or slows down dashboard queries.
enum HistoryStore {

    // MARK: - Public

    /// Location of the persistent history database.
    /// Creates the file and schema on first call if needed.
    nonisolated static func databaseURL() throws -> URL {
        let base = try applicationSupportDirectory()
        let url = base.appendingPathComponent("screentime.db")
        try ensureSchema(at: url)
        return url
    }

    /// Location of the input-tracking database (keystrokes, mouse, aggregates).
    /// Separate from `screentime.db` so the high-volume mouse_events table doesn't
    /// pessimize unrelated dashboard / menu-bar queries.
    nonisolated static func inputTrackingDatabaseURL() throws -> URL {
        let base = try applicationSupportDirectory()
        let url = base.appendingPathComponent("input-tracking.db")
        try ensureInputTrackingSchema(at: url)
        try migrateInputTrackingFromMainDBIfNeeded(newURL: url, baseDirectory: base)
        return url
    }

    /// Location of the web-history archive database.
    /// Separate from `screentime.db` so archived browser visits do not inflate
    /// the screen-time analytics store.
    nonisolated static func webHistoryDatabaseURL() throws -> URL {
        let base = try applicationSupportDirectory()
        let url = base.appendingPathComponent("web-history.db")
        try ensureWebHistorySchema(at: url)
        try migrateWebHistoryFromMainDBIfNeeded(newURL: url, baseDirectory: base)
        return url
    }

    nonisolated private static func applicationSupportDirectory() throws -> URL {
        let base = realHomeDirectory()
            .appendingPathComponent("Library/Application Support/time.md", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Schema

    nonisolated private static func ensureSchema(at url: URL) throws {
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
        CREATE INDEX IF NOT EXISTS idx_usage_stream_start_time ON usage(stream_type, start_time);
        CREATE INDEX IF NOT EXISTS idx_usage_metadata_start_time ON usage(metadata_hash, start_time);
        CREATE INDEX IF NOT EXISTS idx_usage_app_start_time ON usage(app_name, start_time);
        CREATE INDEX IF NOT EXISTS idx_usage_duration_start_time ON usage(duration_seconds DESC, start_time);
        """
        guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: url.path, message: String(cString: sqlite3_errmsg(db)))
        }

        // Drop the old dedup index that didn't include stream_type.
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_usage_dedup", nil, nil, nil)

        try ensureUsageRollupSchema(db: db, path: url.path)
    }

    // MARK: - Usage rollup schema

    nonisolated private static func ensureUsageRollupSchema(db: OpaquePointer, path: String) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS usage_hourly_app_rollups (
            day TEXT NOT NULL,
            hour INTEGER NOT NULL,
            app_name TEXT NOT NULL,
            stream_type TEXT NOT NULL,
            rollup_scope TEXT NOT NULL,
            total_seconds REAL NOT NULL,
            session_count INTEGER NOT NULL,
            PRIMARY KEY (day, hour, app_name, stream_type, rollup_scope)
        );
        CREATE INDEX IF NOT EXISTS idx_usage_hourly_app_rollups_scope_day ON usage_hourly_app_rollups(rollup_scope, day);
        CREATE INDEX IF NOT EXISTS idx_usage_hourly_app_rollups_app_day ON usage_hourly_app_rollups(app_name, day);
        CREATE TABLE IF NOT EXISTS usage_rollup_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TRIGGER IF NOT EXISTS trg_usage_hourly_rollup_insert AFTER INSERT ON usage
        BEGIN
            INSERT INTO usage_hourly_app_rollups(day, hour, app_name, stream_type, rollup_scope, total_seconds, session_count)
            VALUES (DATE(NEW.start_time), CAST(STRFTIME('%H', NEW.start_time) AS INTEGER), NEW.app_name, NEW.stream_type, 'all', NEW.duration_seconds, 1)
            ON CONFLICT(day, hour, app_name, stream_type, rollup_scope) DO UPDATE SET
                total_seconds = total_seconds + NEW.duration_seconds,
                session_count = session_count + 1;

            INSERT INTO usage_hourly_app_rollups(day, hour, app_name, stream_type, rollup_scope, total_seconds, session_count)
            SELECT DATE(NEW.start_time), CAST(STRFTIME('%H', NEW.start_time) AS INTEGER), NEW.app_name, NEW.stream_type, 'direct', NEW.duration_seconds, 1
            WHERE NEW.metadata_hash = 'direct_observation'
            ON CONFLICT(day, hour, app_name, stream_type, rollup_scope) DO UPDATE SET
                total_seconds = total_seconds + NEW.duration_seconds,
                session_count = session_count + 1;
        END;

        CREATE TRIGGER IF NOT EXISTS trg_usage_hourly_rollup_delete AFTER DELETE ON usage
        BEGIN
            UPDATE usage_hourly_app_rollups
            SET total_seconds = MAX(total_seconds - OLD.duration_seconds, 0),
                session_count = session_count - 1
            WHERE day = DATE(OLD.start_time)
              AND hour = CAST(STRFTIME('%H', OLD.start_time) AS INTEGER)
              AND app_name = OLD.app_name
              AND stream_type = OLD.stream_type
              AND rollup_scope = 'all';
            DELETE FROM usage_hourly_app_rollups WHERE session_count <= 0;

            UPDATE usage_hourly_app_rollups
            SET total_seconds = MAX(total_seconds - OLD.duration_seconds, 0),
                session_count = session_count - 1
            WHERE OLD.metadata_hash = 'direct_observation'
              AND day = DATE(OLD.start_time)
              AND hour = CAST(STRFTIME('%H', OLD.start_time) AS INTEGER)
              AND app_name = OLD.app_name
              AND stream_type = OLD.stream_type
              AND rollup_scope = 'direct';
            DELETE FROM usage_hourly_app_rollups WHERE session_count <= 0;
        END;

        CREATE TRIGGER IF NOT EXISTS trg_usage_hourly_rollup_update AFTER UPDATE ON usage
        BEGIN
            UPDATE usage_hourly_app_rollups
            SET total_seconds = MAX(total_seconds - OLD.duration_seconds, 0),
                session_count = session_count - 1
            WHERE day = DATE(OLD.start_time)
              AND hour = CAST(STRFTIME('%H', OLD.start_time) AS INTEGER)
              AND app_name = OLD.app_name
              AND stream_type = OLD.stream_type
              AND rollup_scope = 'all';
            DELETE FROM usage_hourly_app_rollups WHERE session_count <= 0;

            UPDATE usage_hourly_app_rollups
            SET total_seconds = MAX(total_seconds - OLD.duration_seconds, 0),
                session_count = session_count - 1
            WHERE OLD.metadata_hash = 'direct_observation'
              AND day = DATE(OLD.start_time)
              AND hour = CAST(STRFTIME('%H', OLD.start_time) AS INTEGER)
              AND app_name = OLD.app_name
              AND stream_type = OLD.stream_type
              AND rollup_scope = 'direct';
            DELETE FROM usage_hourly_app_rollups WHERE session_count <= 0;

            INSERT INTO usage_hourly_app_rollups(day, hour, app_name, stream_type, rollup_scope, total_seconds, session_count)
            VALUES (DATE(NEW.start_time), CAST(STRFTIME('%H', NEW.start_time) AS INTEGER), NEW.app_name, NEW.stream_type, 'all', NEW.duration_seconds, 1)
            ON CONFLICT(day, hour, app_name, stream_type, rollup_scope) DO UPDATE SET
                total_seconds = total_seconds + NEW.duration_seconds,
                session_count = session_count + 1;

            INSERT INTO usage_hourly_app_rollups(day, hour, app_name, stream_type, rollup_scope, total_seconds, session_count)
            SELECT DATE(NEW.start_time), CAST(STRFTIME('%H', NEW.start_time) AS INTEGER), NEW.app_name, NEW.stream_type, 'direct', NEW.duration_seconds, 1
            WHERE NEW.metadata_hash = 'direct_observation'
            ON CONFLICT(day, hour, app_name, stream_type, rollup_scope) DO UPDATE SET
                total_seconds = total_seconds + NEW.duration_seconds,
                session_count = session_count + 1;
        END;
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: String(cString: sqlite3_errmsg(db)))
        }

        try backfillUsageRollupsIfNeeded(db: db, path: path)
    }

    nonisolated private static func backfillUsageRollupsIfNeeded(db: OpaquePointer, path: String) throws {
        guard !localMetaExists(db: db, table: "usage_rollup_meta", key: "hourly_app_backfilled_v1") else { return }

        let sql = """
        BEGIN IMMEDIATE;
        DELETE FROM usage_hourly_app_rollups;

        INSERT INTO usage_hourly_app_rollups(day, hour, app_name, stream_type, rollup_scope, total_seconds, session_count)
        SELECT
            DATE(start_time) AS day,
            CAST(STRFTIME('%H', start_time) AS INTEGER) AS hour,
            app_name,
            stream_type,
            'all' AS rollup_scope,
            SUM(duration_seconds),
            COUNT(*)
        FROM usage
        GROUP BY day, hour, app_name, stream_type;

        INSERT INTO usage_hourly_app_rollups(day, hour, app_name, stream_type, rollup_scope, total_seconds, session_count)
        SELECT
            DATE(start_time) AS day,
            CAST(STRFTIME('%H', start_time) AS INTEGER) AS hour,
            app_name,
            stream_type,
            'direct' AS rollup_scope,
            SUM(duration_seconds),
            COUNT(*)
        FROM usage
        WHERE metadata_hash = 'direct_observation'
        GROUP BY day, hour, app_name, stream_type;

        INSERT OR REPLACE INTO usage_rollup_meta(key, value) VALUES ('hourly_app_backfilled_v1', '1');
        COMMIT;
        """

        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
                sqlite3_free(errorPointer)
            } else {
                message = String(cString: sqlite3_errmsg(db))
            }
            throw ScreenTimeDataError.sqlite(path: path, message: message)
        }
    }

    nonisolated private static func localMetaExists(db: OpaquePointer, table: String, key: String) -> Bool {
        let sql = "SELECT 1 FROM \(table) WHERE key = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return false }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    // MARK: - Input tracking schema + migration

    /// Tables backing the opt-in input tracker (keystrokes, mouse events, and
    /// derived aggregates). Lives in `input-tracking.db` so the high-volume
    /// mouse_events table doesn't bloat the main DB.
    nonisolated private static func ensureInputTrackingSchema(at url: URL) throws {
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
    nonisolated private static let migrationFlagKey = "inputTrackingMigratedToSeparateDB_v1"

    nonisolated private static func migrateInputTrackingFromMainDBIfNeeded(newURL: URL, baseDirectory: URL) throws {
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

    nonisolated private static func legacyHasTable(db: OpaquePointer, name: String) -> Bool {
        let sql = "SELECT 1 FROM legacy.sqlite_master WHERE type='table' AND name = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return false }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, name, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    // MARK: - Web history schema + migration

    /// Tables backing the opt-in web history archive. Lives in `web-history.db`
    /// so archived browser visits do not add bulk to `screentime.db`.
    nonisolated private static func ensureWebHistorySchema(at url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard result == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw ScreenTimeDataError.sqlite(path: url.path, message: "Failed to open web-history database")
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_busy_timeout(db, 5000)

        let createSQL = """
        CREATE TABLE IF NOT EXISTS web_history_visits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            browser TEXT NOT NULL,
            url TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            domain TEXT NOT NULL DEFAULT '',
            visit_time REAL NOT NULL,
            duration_seconds REAL,
            first_seen_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            UNIQUE(browser, visit_time, url)
        );
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: url.path, message: String(cString: sqlite3_errmsg(db)))
        }

        let indexSQL = """
        CREATE INDEX IF NOT EXISTS idx_web_history_visit_time ON web_history_visits(visit_time);
        CREATE INDEX IF NOT EXISTS idx_web_history_browser_time ON web_history_visits(browser, visit_time);
        CREATE INDEX IF NOT EXISTS idx_web_history_domain_time ON web_history_visits(domain, visit_time);
        CREATE INDEX IF NOT EXISTS idx_web_history_domain_lower_time ON web_history_visits(LOWER(domain), visit_time);
        """
        guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: url.path, message: String(cString: sqlite3_errmsg(db)))
        }

        let rollupSQL = """
        CREATE TABLE IF NOT EXISTS web_history_daily_counts (
            day TEXT NOT NULL,
            browser TEXT NOT NULL,
            visit_count INTEGER NOT NULL,
            PRIMARY KEY (day, browser)
        );
        CREATE TABLE IF NOT EXISTS web_history_hourly_counts (
            day TEXT NOT NULL,
            hour INTEGER NOT NULL,
            browser TEXT NOT NULL,
            visit_count INTEGER NOT NULL,
            PRIMARY KEY (day, hour, browser)
        );
        CREATE TABLE IF NOT EXISTS web_history_domain_rollups (
            day TEXT NOT NULL,
            browser TEXT NOT NULL,
            domain TEXT NOT NULL,
            visit_count INTEGER NOT NULL,
            total_duration_seconds REAL NOT NULL DEFAULT 0,
            last_visit_time REAL NOT NULL,
            PRIMARY KEY (day, browser, domain)
        );
        CREATE INDEX IF NOT EXISTS idx_web_history_domain_rollups_domain_day ON web_history_domain_rollups(domain, day);
        CREATE INDEX IF NOT EXISTS idx_web_history_domain_rollups_day_count ON web_history_domain_rollups(day, visit_count);
        CREATE TABLE IF NOT EXISTS web_history_rollup_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TRIGGER IF NOT EXISTS trg_web_history_rollup_insert AFTER INSERT ON web_history_visits
        BEGIN
            INSERT INTO web_history_daily_counts(day, browser, visit_count)
            VALUES (DATE(NEW.visit_time, 'unixepoch', 'localtime'), NEW.browser, 1)
            ON CONFLICT(day, browser) DO UPDATE SET visit_count = visit_count + 1;

            INSERT INTO web_history_hourly_counts(day, hour, browser, visit_count)
            VALUES (
                DATE(NEW.visit_time, 'unixepoch', 'localtime'),
                CAST(STRFTIME('%H', NEW.visit_time, 'unixepoch', 'localtime') AS INTEGER),
                NEW.browser,
                1
            )
            ON CONFLICT(day, hour, browser) DO UPDATE SET visit_count = visit_count + 1;

            INSERT INTO web_history_domain_rollups(day, browser, domain, visit_count, total_duration_seconds, last_visit_time)
            SELECT
                DATE(NEW.visit_time, 'unixepoch', 'localtime'),
                NEW.browser,
                NEW.domain,
                1,
                COALESCE(NEW.duration_seconds, 0),
                NEW.visit_time
            WHERE NEW.domain != ''
            ON CONFLICT(day, browser, domain) DO UPDATE SET
                visit_count = visit_count + 1,
                total_duration_seconds = total_duration_seconds + COALESCE(NEW.duration_seconds, 0),
                last_visit_time = MAX(last_visit_time, NEW.visit_time);
        END;

        CREATE TRIGGER IF NOT EXISTS trg_web_history_rollup_delete AFTER DELETE ON web_history_visits
        BEGIN
            UPDATE web_history_daily_counts
            SET visit_count = visit_count - 1
            WHERE day = DATE(OLD.visit_time, 'unixepoch', 'localtime') AND browser = OLD.browser;
            DELETE FROM web_history_daily_counts WHERE visit_count <= 0;

            UPDATE web_history_hourly_counts
            SET visit_count = visit_count - 1
            WHERE day = DATE(OLD.visit_time, 'unixepoch', 'localtime')
              AND hour = CAST(STRFTIME('%H', OLD.visit_time, 'unixepoch', 'localtime') AS INTEGER)
              AND browser = OLD.browser;
            DELETE FROM web_history_hourly_counts WHERE visit_count <= 0;

            UPDATE web_history_domain_rollups
            SET visit_count = visit_count - 1,
                total_duration_seconds = MAX(total_duration_seconds - COALESCE(OLD.duration_seconds, 0), 0)
            WHERE day = DATE(OLD.visit_time, 'unixepoch', 'localtime')
              AND browser = OLD.browser
              AND domain = OLD.domain;
            DELETE FROM web_history_domain_rollups WHERE visit_count <= 0;
        END;

        CREATE TRIGGER IF NOT EXISTS trg_web_history_rollup_update AFTER UPDATE ON web_history_visits
        BEGIN
            UPDATE web_history_daily_counts
            SET visit_count = visit_count - 1
            WHERE day = DATE(OLD.visit_time, 'unixepoch', 'localtime') AND browser = OLD.browser;
            DELETE FROM web_history_daily_counts WHERE visit_count <= 0;
            INSERT INTO web_history_daily_counts(day, browser, visit_count)
            VALUES (DATE(NEW.visit_time, 'unixepoch', 'localtime'), NEW.browser, 1)
            ON CONFLICT(day, browser) DO UPDATE SET visit_count = visit_count + 1;

            UPDATE web_history_hourly_counts
            SET visit_count = visit_count - 1
            WHERE day = DATE(OLD.visit_time, 'unixepoch', 'localtime')
              AND hour = CAST(STRFTIME('%H', OLD.visit_time, 'unixepoch', 'localtime') AS INTEGER)
              AND browser = OLD.browser;
            DELETE FROM web_history_hourly_counts WHERE visit_count <= 0;
            INSERT INTO web_history_hourly_counts(day, hour, browser, visit_count)
            VALUES (
                DATE(NEW.visit_time, 'unixepoch', 'localtime'),
                CAST(STRFTIME('%H', NEW.visit_time, 'unixepoch', 'localtime') AS INTEGER),
                NEW.browser,
                1
            )
            ON CONFLICT(day, hour, browser) DO UPDATE SET visit_count = visit_count + 1;

            UPDATE web_history_domain_rollups
            SET visit_count = visit_count - 1,
                total_duration_seconds = MAX(total_duration_seconds - COALESCE(OLD.duration_seconds, 0), 0)
            WHERE day = DATE(OLD.visit_time, 'unixepoch', 'localtime')
              AND browser = OLD.browser
              AND domain = OLD.domain;
            DELETE FROM web_history_domain_rollups WHERE visit_count <= 0;
            INSERT INTO web_history_domain_rollups(day, browser, domain, visit_count, total_duration_seconds, last_visit_time)
            SELECT
                DATE(NEW.visit_time, 'unixepoch', 'localtime'),
                NEW.browser,
                NEW.domain,
                1,
                COALESCE(NEW.duration_seconds, 0),
                NEW.visit_time
            WHERE NEW.domain != ''
            ON CONFLICT(day, browser, domain) DO UPDATE SET
                visit_count = visit_count + 1,
                total_duration_seconds = total_duration_seconds + COALESCE(NEW.duration_seconds, 0),
                last_visit_time = MAX(last_visit_time, NEW.visit_time);
        END;
        """
        guard sqlite3_exec(db, rollupSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: url.path, message: String(cString: sqlite3_errmsg(db)))
        }

        try backfillWebHistoryRollupsIfNeeded(db: db, path: url.path)
    }

    nonisolated private static func backfillWebHistoryRollupsIfNeeded(db: OpaquePointer, path: String) throws {
        guard !webHistoryRollupMetaExists(db: db, key: "backfilled_v1") else { return }

        let sql = """
        BEGIN IMMEDIATE;
        DELETE FROM web_history_daily_counts;
        DELETE FROM web_history_hourly_counts;
        DELETE FROM web_history_domain_rollups;

        INSERT INTO web_history_daily_counts(day, browser, visit_count)
        SELECT DATE(visit_time, 'unixepoch', 'localtime') AS day, browser, COUNT(*)
        FROM web_history_visits
        GROUP BY day, browser;

        INSERT INTO web_history_hourly_counts(day, hour, browser, visit_count)
        SELECT
            DATE(visit_time, 'unixepoch', 'localtime') AS day,
            CAST(STRFTIME('%H', visit_time, 'unixepoch', 'localtime') AS INTEGER) AS hour,
            browser,
            COUNT(*)
        FROM web_history_visits
        GROUP BY day, hour, browser;

        INSERT INTO web_history_domain_rollups(day, browser, domain, visit_count, total_duration_seconds, last_visit_time)
        SELECT
            DATE(visit_time, 'unixepoch', 'localtime') AS day,
            browser,
            domain,
            COUNT(*),
            COALESCE(SUM(duration_seconds), 0),
            MAX(visit_time)
        FROM web_history_visits
        WHERE domain != ''
        GROUP BY day, browser, domain;

        INSERT OR REPLACE INTO web_history_rollup_meta(key, value) VALUES ('backfilled_v1', '1');
        COMMIT;
        """

        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
                sqlite3_free(errorPointer)
            } else {
                message = String(cString: sqlite3_errmsg(db))
            }
            throw ScreenTimeDataError.sqlite(path: path, message: message)
        }
    }

    nonisolated private static func webHistoryRollupMetaExists(db: OpaquePointer, key: String) -> Bool {
        let sql = "SELECT 1 FROM web_history_rollup_meta WHERE key = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else { return false }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// One-shot migration: copy legacy archive rows out of `screentime.db` into
    /// `web-history.db`. This is intentionally non-destructive; the legacy table
    /// is left in place for rollback safety and can be reclaimed by a later
    /// explicit compaction/migration.
    nonisolated private static let webHistoryMigrationFlagKey = "webHistoryMigratedToSeparateDB_v1"

    nonisolated private static func migrateWebHistoryFromMainDBIfNeeded(newURL: URL, baseDirectory: URL) throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: webHistoryMigrationFlagKey) else { return }

        let oldURL = baseDirectory.appendingPathComponent("screentime.db")
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            defaults.set(true, forKey: webHistoryMigrationFlagKey)
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

        guard legacyHasTable(db: db, name: "web_history_visits") else {
            defaults.set(true, forKey: webHistoryMigrationFlagKey)
            return
        }

        let migrationSQL = """
        BEGIN IMMEDIATE;
        INSERT OR IGNORE INTO main.web_history_visits
            (browser, url, title, domain, visit_time, duration_seconds, first_seen_at, last_seen_at)
            SELECT browser, url, title, domain, visit_time, duration_seconds, first_seen_at, last_seen_at
            FROM legacy.web_history_visits;
        COMMIT;
        """
        var errorPointer: UnsafeMutablePointer<CChar>?
        let execResult = sqlite3_exec(db, migrationSQL, nil, nil, &errorPointer)
        if execResult == SQLITE_OK {
            defaults.set(true, forKey: webHistoryMigrationFlagKey)
        } else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            if let errorPointer {
                NSLog("[HistoryStore] web history migration failed: \(String(cString: errorPointer))")
                sqlite3_free(errorPointer)
            }
        }
    }
}
