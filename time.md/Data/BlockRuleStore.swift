import Foundation
import SQLite3

/// SQLite-backed persistence for blocking rules, per-target state, and audit
/// events. This store intentionally lives in its own database so intervention
/// features cannot bloat or corrupt analytics data in `screentime.db`.
enum BlockRuleStore {
    static let environmentOverrideKey = "TIMEMD_BLOCKING_DB_PATH"

    // MARK: - Database lifecycle

    static func databaseURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let overridePath = environment[environmentOverrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            let url = URL(fileURLWithPath: (overridePath as NSString).expandingTildeInPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try ensureSchema(at: url)
            return url
        }

        let base = realHomeDirectory()
            .appendingPathComponent("Library/Application Support/time.md", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("blocking-rules.db")
        try ensureSchema(at: url)
        return url
    }

    // MARK: - Rules

    static func fetchRules(includeDisabled: Bool = true) throws -> [BlockRule] {
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let disabledClause = includeDisabled ? "" : "WHERE enabled = 1"
        let sql = """
        SELECT id, target_type, target_value, target_display_name, policy_json,
               enabled, enforcement_mode, priority, created_at, updated_at
        FROM block_rules
        \(disabledClause)
        ORDER BY priority DESC, updated_at DESC, target_value ASC
        """

        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        var rules: [BlockRule] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                if let rule = decodeRuleRow(statement: statement) {
                    rules.append(rule)
                }
                continue
            }
            if step == SQLITE_DONE { break }
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        return rules
    }

    static func upsert(rule: BlockRule) throws {
        try rule.policy.validate()
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let policyData = try jsonEncoder.encode(rule.policy)
        guard let policyJSON = String(data: policyData, encoding: .utf8) else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: "Unable to encode block policy JSON")
        }

        let sql = """
        INSERT INTO block_rules (
            id, target_type, target_value, target_display_name, policy_json,
            enabled, enforcement_mode, priority, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            target_type = excluded.target_type,
            target_value = excluded.target_value,
            target_display_name = excluded.target_display_name,
            policy_json = excluded.policy_json,
            enabled = excluded.enabled,
            enforcement_mode = excluded.enforcement_mode,
            priority = excluded.priority,
            updated_at = excluded.updated_at
        """

        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, rule.id.uuidString)
        bindText(statement, 2, rule.target.type.rawValue)
        bindText(statement, 3, rule.target.value)
        bindOptionalText(statement, 4, rule.target.displayName)
        bindText(statement, 5, policyJSON)
        sqlite3_bind_int(statement, 6, rule.enabled ? 1 : 0)
        bindText(statement, 7, rule.enforcementMode.rawValue)
        sqlite3_bind_int(statement, 8, Int32(rule.priority))
        sqlite3_bind_double(statement, 9, rule.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 10, rule.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
    }

    /// Deletes a rule definition. By default, per-target state is retained so
    /// users can disable/delete/recreate a rule without accidentally resetting
    /// strike history. Pass `deleteState: true` when a caller intentionally wants
    /// to remove the state for the deleted rule's target as well.
    static func deleteRule(id: UUID, deleteState: Bool = false) throws {
        let target = deleteState ? try fetchRule(id: id)?.target : nil
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let sql = "DELETE FROM block_rules WHERE id = ?"
        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, id.uuidString)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }

        if let target {
            try Self.deleteState(for: target)
        }
    }

    static func fetchRule(id: UUID) throws -> BlockRule? {
        try fetchRules().first { $0.id == id }
    }

    // MARK: - State

    static func fetchStates() throws -> [BlockState] {
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let sql = """
        SELECT target_type, target_value, target_display_name, rule_id, strike_count,
               blocked_until, last_allowed_at, last_blocked_at, updated_at
        FROM block_states
        ORDER BY updated_at DESC, target_value ASC
        """

        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        var states: [BlockState] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                if let state = decodeStateRow(statement: statement) {
                    states.append(state)
                }
                continue
            }
            if step == SQLITE_DONE { break }
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        return states
    }

    static func fetchState(for target: BlockTarget) throws -> BlockState? {
        try fetchStates().first { $0.target.type == target.type && $0.target.value == target.value }
    }

    static func upsert(state: BlockState) throws {
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let sql = """
        INSERT INTO block_states (
            target_type, target_value, target_display_name, rule_id, strike_count,
            blocked_until, last_allowed_at, last_blocked_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(target_type, target_value) DO UPDATE SET
            target_display_name = excluded.target_display_name,
            rule_id = excluded.rule_id,
            strike_count = excluded.strike_count,
            blocked_until = excluded.blocked_until,
            last_allowed_at = excluded.last_allowed_at,
            last_blocked_at = excluded.last_blocked_at,
            updated_at = excluded.updated_at
        """

        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, state.target.type.rawValue)
        bindText(statement, 2, state.target.value)
        bindOptionalText(statement, 3, state.target.displayName)
        bindOptionalText(statement, 4, state.ruleID?.uuidString)
        sqlite3_bind_int(statement, 5, Int32(state.strikeCount))
        bindOptionalDate(statement, 6, state.blockedUntil)
        bindOptionalDate(statement, 7, state.lastAllowedAt)
        bindOptionalDate(statement, 8, state.lastBlockedAt)
        sqlite3_bind_double(statement, 9, state.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
    }

    static func deleteState(for target: BlockTarget) throws {
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let sql = "DELETE FROM block_states WHERE target_type = ? AND target_value = ?"
        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, target.type.rawValue)
        bindText(statement, 2, target.value)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
    }

    // MARK: - Audit events

    static func appendAuditEvent(_ event: BlockAuditEvent) throws {
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let metadataData = try jsonEncoder.encode(event.metadata)
        guard let metadataJSON = String(data: metadataData, encoding: .utf8) else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: "Unable to encode block audit metadata JSON")
        }

        let sql = """
        INSERT INTO block_audit_events (
            id, timestamp, kind, target_type, target_value, target_display_name,
            rule_id, message, metadata_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, event.id.uuidString)
        sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
        bindText(statement, 3, event.kind.rawValue)
        bindOptionalText(statement, 4, event.target?.type.rawValue)
        bindOptionalText(statement, 5, event.target?.value)
        bindOptionalText(statement, 6, event.target?.displayName)
        bindOptionalText(statement, 7, event.ruleID?.uuidString)
        bindText(statement, 8, event.message)
        bindText(statement, 9, metadataJSON)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
    }

    static func fetchAuditEvents(limit: Int = 100) throws -> [BlockAuditEvent] {
        let database = try openDatabase(readOnly: false)
        defer { sqlite3_close(database.handle) }

        let sql = """
        SELECT id, timestamp, kind, target_type, target_value, target_display_name,
               rule_id, message, metadata_json
        FROM block_audit_events
        ORDER BY timestamp DESC
        LIMIT ?
        """

        var statementPointer: OpaquePointer?
        guard sqlite3_prepare_v2(database.handle, sql, -1, &statementPointer, nil) == SQLITE_OK,
              let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))

        var events: [BlockAuditEvent] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                if let event = decodeAuditEventRow(statement: statement) {
                    events.append(event)
                }
                continue
            }
            if step == SQLITE_DONE { break }
            throw ScreenTimeDataError.sqlite(path: database.path, message: sqliteMessage(db: database.handle))
        }
        return events
    }
}

private extension BlockRuleStore {
    struct OpenedDatabase {
        let path: String
        let handle: OpaquePointer
    }

    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let jsonDecoder = JSONDecoder()

    static func openDatabase(readOnly: Bool) throws -> OpenedDatabase {
        let url = try databaseURL()
        var handlePointer: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        let openResult = sqlite3_open_v2(url.path, &handlePointer, flags, nil)
        guard openResult == SQLITE_OK, let handle = handlePointer else {
            let message = handlePointer.map { sqliteMessage(db: $0) } ?? "Unable to open blocking rules database"
            if let handlePointer { sqlite3_close(handlePointer) }
            throw ScreenTimeDataError.sqlite(path: url.path, message: message)
        }

        sqlite3_busy_timeout(handle, 5000)
        return OpenedDatabase(path: url.path, handle: handle)
    }

    static func ensureSchema(at url: URL) throws {
        var handlePointer: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &handlePointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let db = handlePointer else {
            if let handlePointer { sqlite3_close(handlePointer) }
            throw ScreenTimeDataError.sqlite(path: url.path, message: "Failed to open blocking rules database")
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_busy_timeout(db, 5000)

        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS block_rules (
            id TEXT PRIMARY KEY,
            target_type TEXT NOT NULL,
            target_value TEXT NOT NULL,
            target_display_name TEXT,
            policy_json TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            enforcement_mode TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(target_type, target_value)
        );

        CREATE TABLE IF NOT EXISTS block_states (
            target_type TEXT NOT NULL,
            target_value TEXT NOT NULL,
            target_display_name TEXT,
            rule_id TEXT,
            strike_count INTEGER NOT NULL DEFAULT 0,
            blocked_until REAL,
            last_allowed_at REAL,
            last_blocked_at REAL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(target_type, target_value)
        );

        CREATE TABLE IF NOT EXISTS block_audit_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            kind TEXT NOT NULL,
            target_type TEXT,
            target_value TEXT,
            target_display_name TEXT,
            rule_id TEXT,
            message TEXT NOT NULL DEFAULT '',
            metadata_json TEXT NOT NULL DEFAULT '{}'
        );

        CREATE INDEX IF NOT EXISTS idx_block_rules_target ON block_rules(target_type, target_value);
        CREATE INDEX IF NOT EXISTS idx_block_rules_enabled ON block_rules(enabled);
        CREATE INDEX IF NOT EXISTS idx_block_states_blocked_until ON block_states(blocked_until);
        CREATE INDEX IF NOT EXISTS idx_block_audit_timestamp ON block_audit_events(timestamp);
        """

        guard sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK else {
            throw ScreenTimeDataError.sqlite(path: url.path, message: sqliteMessage(db: db))
        }
    }

    static func decodeRuleRow(statement: OpaquePointer) -> BlockRule? {
        do {
            guard let idString = sqliteColumnText(statement: statement, index: 0),
                  let id = UUID(uuidString: idString),
                  let typeString = sqliteColumnText(statement: statement, index: 1),
                  let type = BlockTargetType(rawValue: typeString),
                  let targetValue = sqliteColumnText(statement: statement, index: 2),
                  let policyJSONString = sqliteColumnText(statement: statement, index: 4),
                  let policyData = policyJSONString.data(using: .utf8),
                  let enforcementString = sqliteColumnText(statement: statement, index: 6),
                  let enforcementMode = BlockEnforcementMode(rawValue: enforcementString) else {
                return nil
            }

            let target = try BlockTarget(
                type: type,
                value: targetValue,
                displayName: sqliteColumnText(statement: statement, index: 3)
            )
            let policy = try jsonDecoder.decode(BlockPolicy.self, from: policyData)
            try policy.validate()

            return BlockRule(
                id: id,
                target: target,
                policy: policy,
                enabled: sqlite3_column_int(statement, 5) != 0,
                enforcementMode: enforcementMode,
                priority: Int(sqlite3_column_int(statement, 7)),
                createdAt: dateColumn(statement: statement, index: 8) ?? Date(timeIntervalSince1970: 0),
                updatedAt: dateColumn(statement: statement, index: 9) ?? Date(timeIntervalSince1970: 0)
            )
        } catch {
            return nil
        }
    }

    static func decodeStateRow(statement: OpaquePointer) -> BlockState? {
        do {
            guard let typeString = sqliteColumnText(statement: statement, index: 0),
                  let type = BlockTargetType(rawValue: typeString),
                  let targetValue = sqliteColumnText(statement: statement, index: 1) else {
                return nil
            }
            let target = try BlockTarget(
                type: type,
                value: targetValue,
                displayName: sqliteColumnText(statement: statement, index: 2)
            )
            let ruleID = sqliteColumnText(statement: statement, index: 3).flatMap(UUID.init(uuidString:))
            let strikeCount = Int(sqlite3_column_int(statement, 4))
            return try BlockState(
                target: target,
                ruleID: ruleID,
                strikeCount: strikeCount,
                blockedUntil: dateColumn(statement: statement, index: 5),
                lastAllowedAt: dateColumn(statement: statement, index: 6),
                lastBlockedAt: dateColumn(statement: statement, index: 7),
                updatedAt: dateColumn(statement: statement, index: 8) ?? Date(timeIntervalSince1970: 0)
            )
        } catch {
            return nil
        }
    }

    static func decodeAuditEventRow(statement: OpaquePointer) -> BlockAuditEvent? {
        do {
            guard let idString = sqliteColumnText(statement: statement, index: 0),
                  let id = UUID(uuidString: idString),
                  let kindString = sqliteColumnText(statement: statement, index: 2),
                  let kind = BlockAuditEventKind(rawValue: kindString) else {
                return nil
            }

            let target: BlockTarget?
            if let typeString = sqliteColumnText(statement: statement, index: 3),
               let type = BlockTargetType(rawValue: typeString),
               let value = sqliteColumnText(statement: statement, index: 4) {
                target = try BlockTarget(
                    type: type,
                    value: value,
                    displayName: sqliteColumnText(statement: statement, index: 5)
                )
            } else {
                target = nil
            }

            let metadataJSONString = sqliteColumnText(statement: statement, index: 8) ?? "{}"
            let metadataData = metadataJSONString.data(using: .utf8) ?? Data()
            let metadata = (try? jsonDecoder.decode([String: String].self, from: metadataData)) ?? [:]

            return BlockAuditEvent(
                id: id,
                timestamp: dateColumn(statement: statement, index: 1) ?? Date(timeIntervalSince1970: 0),
                kind: kind,
                target: target,
                ruleID: sqliteColumnText(statement: statement, index: 6).flatMap(UUID.init(uuidString:)),
                message: sqliteColumnText(statement: statement, index: 7) ?? "",
                metadata: metadata
            )
        } catch {
            return nil
        }
    }

    static func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    static func bindOptionalText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            bindText(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func bindOptionalDate(_ statement: OpaquePointer, _ index: Int32, _ value: Date?) {
        if let value {
            sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func dateColumn(statement: OpaquePointer, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    static func sqliteColumnText(statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    static func sqliteMessage(db: OpaquePointer) -> String {
        guard let cString = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: cString)
    }
}
