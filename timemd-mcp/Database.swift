import Foundation
import SQLite3

enum DatabaseError: Error, CustomStringConvertible {
    case openFailed(path: String, message: String)
    case prepareFailed(sql: String, message: String)
    case bindFailed(index: Int32, message: String)
    case stepFailed(message: String)
    case notReadOnly(sql: String)

    var description: String {
        switch self {
        case .openFailed(let path, let message):
            return "Failed to open database at \(path): \(message)"
        case .prepareFailed(let sql, let message):
            return "SQL prepare failed: \(message)\nSQL: \(sql)"
        case .bindFailed(let index, let message):
            return "Bind failed at index \(index): \(message)"
        case .stepFailed(let message):
            return "SQL step failed: \(message)"
        case .notReadOnly(let sql):
            return "Only SELECT/WITH/EXPLAIN queries are allowed: \(sql)"
        }
    }
}

enum SQLValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)

    var jsonValue: Any {
        switch self {
        case .null: return NSNull()
        case .int(let v): return v
        case .double(let v): return v
        case .text(let v): return v
        }
    }
}

final class Database {
    private let handle: OpaquePointer
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static let screentimeDBPath: String = {
        NSHomeDirectory() + "/Library/Application Support/time.md/screentime.db"
    }()

    static let categoryMappingsDBPath: String = {
        NSHomeDirectory() + "/Library/Application Support/time.md/category-mappings.db"
    }()

    static let currentSessionPath: String = {
        NSHomeDirectory() + "/Library/Application Support/time.md/current_session.json"
    }()

    // MARK: - Current session hint

    struct CurrentSession {
        let appName: String
        let startTimestamp: Double
        let streamType: String

        var elapsedSeconds: Double { Date().timeIntervalSince1970 - startTimestamp }
    }

    /// Reads the hint file written by ActiveAppTracker for the currently active app.
    /// Returns nil if the file is missing, unreadable, or malformed.
    func currentSession() -> CurrentSession? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Database.currentSessionPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appName = obj["app_name"] as? String,
              let startTimestamp = obj["start_timestamp"] as? Double,
              startTimestamp > 0
        else { return nil }
        let streamType = obj["stream_type"] as? String ?? "app_usage"
        return CurrentSession(appName: appName, startTimestamp: startTimestamp, streamType: streamType)
    }

    init() throws {
        var h: OpaquePointer?
        let result = sqlite3_open_v2(
            Database.screentimeDBPath,
            &h,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle = h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = h { sqlite3_close(h) }
            throw DatabaseError.openFailed(path: Database.screentimeDBPath, message: msg)
        }
        self.handle = handle
        sqlite3_busy_timeout(handle, 5000)

        if FileManager.default.fileExists(atPath: Database.categoryMappingsDBPath) {
            let attachSQL = "ATTACH DATABASE ? AS cat"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(handle, attachSQL, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
                sqlite3_bind_text(stmt, 1, Database.categoryMappingsDBPath, -1, sqliteTransient)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    var hasCategoryMappings: Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM cat.sqlite_master WHERE type='table' AND name='app_category_map'"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    func query(_ sql: String, bindings: [SQLValue] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        let prepare = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prepare == SQLITE_OK, let statement = stmt else {
            let message = String(cString: sqlite3_errmsg(handle))
            if let stmt = stmt { sqlite3_finalize(stmt) }
            throw DatabaseError.prepareFailed(sql: sql, message: message)
        }
        defer { sqlite3_finalize(statement) }

        for (i, binding) in bindings.enumerated() {
            let index = Int32(i + 1)
            let rc: Int32
            switch binding {
            case .null:
                rc = sqlite3_bind_null(statement, index)
            case .int(let v):
                rc = sqlite3_bind_int64(statement, index, v)
            case .double(let v):
                rc = sqlite3_bind_double(statement, index, v)
            case .text(let v):
                rc = sqlite3_bind_text(statement, index, v, -1, sqliteTransient)
            }
            guard rc == SQLITE_OK else {
                throw DatabaseError.bindFailed(index: index, message: String(cString: sqlite3_errmsg(handle)))
            }
        }

        var rows: [[String: Any]] = []
        let columnCount = sqlite3_column_count(statement)
        var columnNames: [String] = []
        for i in 0..<columnCount {
            columnNames.append(String(cString: sqlite3_column_name(statement, i)))
        }

        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw DatabaseError.stepFailed(message: String(cString: sqlite3_errmsg(handle)))
            }
            var row: [String: Any] = [:]
            for i in 0..<columnCount {
                let columnType = sqlite3_column_type(statement, i)
                let name = columnNames[Int(i)]
                switch columnType {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let c = sqlite3_column_text(statement, i) {
                        row[name] = String(cString: c)
                    } else {
                        row[name] = NSNull()
                    }
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    row[name] = NSNull()
                }
            }
            rows.append(row)
        }
        return rows
    }

    func queryReadOnlyRaw(_ sql: String) throws -> [[String: Any]] {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let upper = trimmed.uppercased()
        let allowed = ["SELECT", "WITH", "EXPLAIN"]
        guard allowed.contains(where: { upper.hasPrefix($0) }) else {
            throw DatabaseError.notReadOnly(sql: sql)
        }
        if upper.contains(";") {
            throw DatabaseError.notReadOnly(sql: sql)
        }
        return try query(trimmed)
    }
}
