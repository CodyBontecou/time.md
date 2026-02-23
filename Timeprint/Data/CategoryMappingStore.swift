import Foundation
import SQLite3

enum CategoryMappingStore {
    static let tableName = "app_category_map"

    static func fetchAll() throws -> [AppCategoryMapping] {
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let rows = try queryMappings(db: database.handle, path: database.path)
        return rows.sorted { lhs, rhs in
            lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
    }

    static func upsert(appName: String, category: String) throws {
        let normalizedApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedApp.isEmpty, !normalizedCategory.isEmpty else {
            return
        }

        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        try ensureSchema(db: database.handle, path: database.path)

        let sql = """
        INSERT INTO \(tableName) (app_name, category)
        VALUES (?, ?)
        ON CONFLICT(app_name) DO UPDATE SET category = excluded.category
        """

        var statementPointer: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil)
        guard prepareResult == SQLITE_OK, let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }

        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, normalizedApp, -1, sqliteTransient) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, normalizedCategory, -1, sqliteTransient) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
    }

    static func delete(appName: String) throws {
        let normalizedApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedApp.isEmpty else {
            return
        }

        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        try ensureSchema(db: database.handle, path: database.path)

        let sql = "DELETE FROM \(tableName) WHERE app_name = ?"
        var statementPointer: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil)
        guard prepareResult == SQLITE_OK, let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }

        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, normalizedApp, -1, sqliteTransient) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
    }

    static func installMappings(into db: OpaquePointer, path: String) throws {
        try ensureSchema(db: db, path: path)

        let mappings = try fetchAll()

        try exec(db: db, sql: "BEGIN IMMEDIATE", path: path)
        do {
            try exec(db: db, sql: "DELETE FROM \(tableName)", path: path)

            let insertSQL = "INSERT INTO \(tableName) (app_name, category) VALUES (?, ?)"
            var statementPointer: OpaquePointer?
            let prepareResult = sqlite3_prepare_v2(db, insertSQL, -1, &statementPointer, nil)
            guard prepareResult == SQLITE_OK, let statement = statementPointer else {
                throw ScreenTimeDataError.sqlite(path: path, message: sqliteMessage(db: db))
            }

            defer { sqlite3_finalize(statement) }

            for mapping in mappings {
                sqlite3_clear_bindings(statement)
                sqlite3_reset(statement)

                guard sqlite3_bind_text(statement, 1, mapping.appName, -1, sqliteTransient) == SQLITE_OK,
                      sqlite3_bind_text(statement, 2, mapping.category, -1, sqliteTransient) == SQLITE_OK else {
                    throw ScreenTimeDataError.sqlite(path: path, message: sqliteMessage(db: db))
                }

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw ScreenTimeDataError.sqlite(path: path, message: sqliteMessage(db: db))
                }
            }

            try exec(db: db, sql: "COMMIT", path: path)
        } catch {
            try? exec(db: db, sql: "ROLLBACK", path: path)
            throw error
        }
    }
}

private extension CategoryMappingStore {
    struct OpenedDatabase {
        let path: String
        let handle: OpaquePointer
    }

    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func openDatabase(readOnly: Bool) throws -> OpenedDatabase {
        let path = try databaseURL().path
        var handlePointer: OpaquePointer?

        let flags: Int32 = {
            if readOnly {
                return SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            }
            return SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        }()

        let openResult = sqlite3_open_v2(path, &handlePointer, flags, nil)

        guard openResult == SQLITE_OK, let handle = handlePointer else {
            let message = handlePointer.map { sqliteMessage(db: $0) } ?? "Unable to open category mapping database"
            if openResult == SQLITE_CANTOPEN || openResult == SQLITE_PERM || openResult == SQLITE_AUTH {
                throw ScreenTimeDataError.permissionDenied(path: path)
            }
            throw ScreenTimeDataError.sqlite(path: path, message: message)
        }

        if !readOnly {
            try ensureSchema(db: handle, path: path)
        }

        return OpenedDatabase(path: path, handle: handle)
    }

    static func databaseURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let overridePath = environment["SCREENTIME_CATEGORY_MAPPINGS_DB_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            let expanded = (overridePath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            let parentDirectory = url.deletingLastPathComponent()

            do {
                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            } catch {
                throw ScreenTimeDataError.permissionDenied(path: parentDirectory.path)
            }

            return url
        }

        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Timeprint", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            throw ScreenTimeDataError.permissionDenied(path: base.path)
        }

        return base.appendingPathComponent("category-mappings.db")
    }

    static func ensureSchema(db: OpaquePointer, path: String) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            app_name TEXT PRIMARY KEY,
            category TEXT NOT NULL
        );
        """

        try exec(db: db, sql: sql, path: path)
    }

    static func queryMappings(db: OpaquePointer, path: String) throws -> [AppCategoryMapping] {
        try ensureSchema(db: db, path: path)

        let sql = "SELECT app_name, category FROM \(tableName)"
        var statementPointer: OpaquePointer?

        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statementPointer, nil)
        guard prepareResult == SQLITE_OK, let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: path, message: sqliteMessage(db: db))
        }

        defer { sqlite3_finalize(statement) }

        var mappings: [AppCategoryMapping] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                let appName = sqliteColumnText(statement: statement, index: 0) ?? ""
                let category = sqliteColumnText(statement: statement, index: 1) ?? ""
                if !appName.isEmpty, !category.isEmpty {
                    mappings.append(AppCategoryMapping(appName: appName, category: category))
                }
                continue
            }

            if step == SQLITE_DONE {
                break
            }

            throw ScreenTimeDataError.sqlite(path: path, message: sqliteMessage(db: db))
        }

        return mappings
    }

    static func exec(db: OpaquePointer, sql: String, path: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: path, message: sqliteMessage(db: db))
        }
    }

    static func sqliteMessage(db: OpaquePointer) -> String {
        guard let cString = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: cString)
    }

    static func sqliteColumnText(statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
}
