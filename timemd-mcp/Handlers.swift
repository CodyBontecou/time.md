import Foundation

enum HandlerError: Error, CustomStringConvertible {
    case missingArgument(String)
    case unknownTool(String)

    var description: String {
        switch self {
        case .missingArgument(let name): return "Missing required argument: \(name)"
        case .unknownTool(let name): return "Unknown tool: \(name)"
        }
    }
}

enum Handlers {
    static func dispatch(name: String, arguments: [String: Any]?, db: Database) throws -> String {
        let args = Args(raw: arguments)
        switch name {
        case "get_schema":          return schema(db: db)
        case "get_range_totals":    return try rangeTotals(args: args, db: db)
        case "get_today":           return try today(args: args, db: db)
        case "get_top_apps":        return try topApps(args: args, db: db)
        case "get_top_categories":  return try topCategories(args: args, db: db)
        case "get_sessions":        return try sessions(args: args, db: db)
        case "get_hourly_distribution": return try hourlyDistribution(args: args, db: db)
        case "get_daily_trend":     return try dailyTrend(args: args, db: db)
        case "get_weekday_breakdown": return try weekdayBreakdown(args: args, db: db)
        case "get_app_detail":      return try appDetail(args: args, db: db)
        case "get_web_usage":       return try streamAggregate(args: args, db: db, streamType: "web_usage")
        case "get_media_usage":     return try streamAggregate(args: args, db: db, streamType: "media_usage")
        case "get_longest_sessions": return try longestSessions(args: args, db: db)
        case "get_session_buckets": return try sessionBuckets(args: args, db: db)
        case "get_focus_blocks":    return try focusBlocks(args: args, db: db)
        case "get_context_switches": return try contextSwitches(args: args, db: db)
        case "get_app_transitions": return try appTransitions(args: args, db: db)
        case "get_devices":         return try devices(db: db)
        case "get_stream_types":    return try streamTypes(db: db)
        case "get_category_mappings": return try categoryMappings(db: db)
        case "compare_periods":     return try comparePeriods(args: args, db: db)
        case "get_heatmap":         return try heatmap(args: args, db: db)
        case "get_daily_app_breakdown": return try dailyAppBreakdown(args: args, db: db)
        case "get_category_trend":  return try categoryTrend(args: args, db: db)
        case "get_first_last_use":  return try firstLastUse(args: args, db: db)
        case "get_active_days":     return try activeDays(args: args, db: db)
        case "get_time_of_day_split": return try timeOfDaySplit(args: args, db: db)
        case "get_weekend_vs_weekday": return try weekendVsWeekday(args: args, db: db)
        case "get_new_apps":        return try newApps(args: args, db: db)
        case "get_abandoned_apps":  return try abandonedApps(args: args, db: db)
        case "get_usage_streaks":   return try usageStreaks(args: args, db: db)
        case "get_pickup_count":    return try pickupCount(args: args, db: db)
        case "get_typical_day":     return try typicalDay(args: args, db: db)
        case "get_metadata_hash_breakdown": return try metadataHashBreakdown(args: args, db: db)
        case "raw_query":           return try rawQuery(args: args, db: db)
        default: throw HandlerError.unknownTool(name)
        }
    }

    // MARK: - Argument wrapper

    private struct Args {
        let raw: [String: Any]?

        func string(_ key: String) -> String? {
            guard let value = raw?[key] else { return nil }
            if let s = value as? String { return s }
            if let n = value as? NSNumber { return n.stringValue }
            return nil
        }

        func requiredString(_ key: String) throws -> String {
            guard let s = string(key), !s.isEmpty else {
                throw HandlerError.missingArgument(key)
            }
            return s
        }

        func int(_ key: String, default fallback: Int) -> Int {
            guard let value = raw?[key] else { return fallback }
            if let i = value as? Int { return i }
            if let i = value as? Int64 { return Int(i) }
            if let d = value as? Double { return Int(d) }
            if let s = value as? String, let i = Int(s) { return i }
            return fallback
        }

        func double(_ key: String, default fallback: Double) -> Double {
            guard let value = raw?[key] else { return fallback }
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            if let i = value as? Int64 { return Double(i) }
            if let s = value as? String, let d = Double(s) { return d }
            return fallback
        }
    }

    // MARK: - Deduplication helper

    /// Returns a SQL AND-fragment (including leading AND) that prefers
    /// direct_observation rows over knowledgeC rows on a per-session basis.
    /// A knowledgeC row is excluded only when a direct_observation row exists
    /// for the exact same (app_name, start_time) — so knowledgeC-only sessions
    /// (periods when the in-app tracker wasn't running) are preserved.
    ///
    /// After appending this to a WHERE clause, push two extra bindings:
    /// rangeStart and rangeEnd (same values used for the main time filter).
    /// These narrow the correlated subquery scan for better performance.
    private static func dedupClause(alias: String = "") -> String {
        let col      = alias.isEmpty ? "metadata_hash" : "\(alias).metadata_hash"
        let nameCol  = alias.isEmpty ? "app_name"      : "\(alias).app_name"
        let timeCol  = alias.isEmpty ? "start_time"    : "\(alias).start_time"
        return """
          AND (\(col) = 'direct_observation'
               OR NOT EXISTS (
                   SELECT 1 FROM usage _dedup
                   WHERE _dedup.app_name        = \(nameCol)
                     AND _dedup.start_time      = \(timeCol)
                     AND _dedup.metadata_hash   = 'direct_observation'
                     AND _dedup.start_time >= ?
                     AND _dedup.start_time <  ?
                   LIMIT 1
               ))
        """
    }

    // MARK: - App name resolution

    /// Resolves a user-friendly app name to the stored app_name (bundle ID).
    /// 1. Exact match — returned as-is.
    /// 2. Fuzzy: strips dots from bundle IDs and spaces from the query, then
    ///    does a case-insensitive LIKE. Picks the highest-usage match.
    ///    "World of Warcraft" → "worldofwarcraft" matches "com.blizzard.worldofwarcraft".
    /// 3. Falls back to the original input (query returns 0 rows gracefully).
    private static func resolveAppName(_ input: String, db: Database) throws -> String {
        // 1. Exact match
        let exact = try db.query(
            "SELECT app_name FROM usage WHERE app_name = ? LIMIT 1",
            bindings: [.text(input)]
        )
        if let match = exact.first?["app_name"] as? String { return match }

        // 2. Fuzzy: collapse dots in bundle IDs and spaces in the query, then LIKE
        let normalized = input.lowercased().replacingOccurrences(of: " ", with: "")
        let fuzzy = try db.query(
            """
            SELECT app_name, SUM(duration_seconds) AS total
            FROM usage
            WHERE REPLACE(LOWER(app_name), '.', '') LIKE ?
            GROUP BY app_name
            ORDER BY total DESC
            LIMIT 1
            """,
            bindings: [.text("%\(normalized)%")]
        )
        if let match = fuzzy.first?["app_name"] as? String { return match }

        // 3. No match — return original so the caller gets 0 results gracefully
        return input
    }

    // MARK: - Live session injection

    /// Returns the current in-progress session if its start falls within [rangeStart, now)
    /// and the range end is still in the future (i.e., this range covers the present moment).
    private static func liveSession(db: Database, rangeStart: String, rangeEnd: String) -> Database.CurrentSession? {
        let now = DateRange.format(Date())
        guard rangeEnd > now, rangeStart <= now else { return nil }
        guard let session = db.currentSession() else { return nil }
        // Sanity: session must have started within this range
        let sessionStart = DateRange.format(Date(timeIntervalSince1970: session.startTimestamp))
        guard sessionStart >= rangeStart else { return nil }
        return session
    }

    /// Injects live session seconds into an array of `[app_name, total_seconds, session_count]` rows.
    /// If the app already appears, its total is incremented. Otherwise a new row is appended.
    /// Result is re-sorted by total_seconds descending.
    private static func injectIntoAppRows(
        _ rows: [[String: Any]],
        appName: String,
        elapsed: Double
    ) -> [[String: Any]] {
        var mutable = rows
        if let idx = mutable.firstIndex(where: { $0["app_name"] as? String == appName }) {
            var row = mutable[idx]
            row["total_seconds"] = (row["total_seconds"] as? Double ?? 0) + elapsed
            mutable[idx] = row
        } else {
            mutable.append(["app_name": appName, "total_seconds": elapsed, "session_count": Int64(1)])
        }
        return mutable.sorted { ($0["total_seconds"] as? Double ?? 0) > ($1["total_seconds"] as? Double ?? 0) }
    }

    /// Injects live session seconds into an array of `[stream_type, total_seconds, session_count]` rows.
    private static func injectIntoStreamRows(
        _ rows: [[String: Any]],
        streamType: String,
        elapsed: Double
    ) -> [[String: Any]] {
        var mutable = rows
        if let idx = mutable.firstIndex(where: { $0["stream_type"] as? String == streamType }) {
            var row = mutable[idx]
            row["total_seconds"] = (row["total_seconds"] as? Double ?? 0) + elapsed
            mutable[idx] = row
        } else {
            mutable.append(["stream_type": streamType, "total_seconds": elapsed, "session_count": Int64(1)])
        }
        return mutable
    }

    // MARK: - Tool implementations

    private static func schema(db: Database) -> String {
        let schema: [String: Any] = [
            "database_path": Database.screentimeDBPath,
            "category_db_path": Database.categoryMappingsDBPath,
            "category_db_attached": db.hasCategoryMappings,
            "tables": [
                [
                    "name": "usage",
                    "description": "One row per observed app/web/media session. The primary time.md data source.",
                    "columns": [
                        ["name": "id", "type": "INTEGER", "description": "Auto-increment primary key."],
                        ["name": "app_name", "type": "TEXT", "description": "App bundle identifier or browser URL for web sessions."],
                        ["name": "duration_seconds", "type": "REAL", "description": "Session length in seconds."],
                        ["name": "start_time", "type": "TEXT", "description": "Local ISO-8601 datetime 'yyyy-MM-ddTHH:mm:ss'."],
                        ["name": "stream_type", "type": "TEXT", "description": "One of app_usage, web_usage, media_usage."],
                        ["name": "source_timestamp", "type": "REAL", "description": "Apple-epoch timestamp used for dedup."],
                        ["name": "device_id", "type": "TEXT", "description": "Hardware UUID of the source device (nullable)."],
                        ["name": "metadata_hash", "type": "TEXT", "description": "Source indicator e.g. 'direct_observation' (in-app tracker) or knowledgeC hashes."]
                    ]
                ],
                [
                    "name": "cat.app_category_map",
                    "description": "User-defined category for each app_name. Lives in a separate database attached as 'cat'.",
                    "columns": [
                        ["name": "app_name", "type": "TEXT", "description": "Primary key — matches usage.app_name."],
                        ["name": "category", "type": "TEXT", "description": "User-assigned category label."]
                    ]
                ]
            ],
            "stream_types": ["app_usage", "web_usage", "media_usage"],
            "metadata_hash_values": ["direct_observation", "knowledgeC (various hashes)"]
        ]
        return toJSON(schema)
    }

    private static func rangeTotals(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        var rows = try db.query(
            """
            SELECT stream_type, SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY stream_type
            ORDER BY total_seconds DESC
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        var grandTotal = rows.reduce(0.0) { $0 + ($1["total_seconds"] as? Double ?? 0) }
        if let live = liveSession(db: db, rangeStart: r.start, rangeEnd: r.end) {
            rows = injectIntoStreamRows(rows, streamType: live.streamType, elapsed: live.elapsedSeconds)
            grandTotal += live.elapsedSeconds
        }
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "total_seconds": grandTotal,
            "by_stream": rows
        ])
    }

    private static func today(args: Args, db: Database) throws -> String {
        let limit = max(1, min(args.int("limit", default: 20), 500))
        let r = try DateRange.parse(since: "today")
        var streams = try db.query(
            """
            SELECT stream_type, SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY stream_type
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        var topAppsRows = try db.query(
            """
            SELECT app_name, SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY app_name
            ORDER BY total_seconds DESC
            LIMIT ?
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end), .int(Int64(limit))]
        )
        var grandTotal = streams.reduce(0.0) { $0 + ($1["total_seconds"] as? Double ?? 0) }
        if let live = liveSession(db: db, rangeStart: r.start, rangeEnd: r.end) {
            streams = injectIntoStreamRows(streams, streamType: live.streamType, elapsed: live.elapsedSeconds)
            topAppsRows = injectIntoAppRows(topAppsRows, appName: live.appName, elapsed: live.elapsedSeconds)
            grandTotal += live.elapsedSeconds
        }
        return toJSON([
            "date": r.start,
            "total_seconds": grandTotal,
            "by_stream": streams,
            "top_apps": topAppsRows
        ])
    }

    private static func topApps(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 25), 500))
        let streamFilter = args.string("stream_type")
        var sql = """
        SELECT app_name, SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
        FROM usage
        WHERE start_time >= ? AND start_time < ?
        """
        var bindings: [SQLValue] = [.text(r.start), .text(r.end)]
        if let s = streamFilter {
            sql += " AND stream_type = ?"
            bindings.append(.text(s))
        }
        sql += dedupClause()
        bindings.append(contentsOf: [.text(r.start), .text(r.end)])
        sql += " GROUP BY app_name ORDER BY total_seconds DESC LIMIT ?"
        bindings.append(.int(Int64(limit)))
        var rows = try db.query(sql, bindings: bindings)
        // Only inject app_usage live session (skip if a different stream is filtered)
        if streamFilter == nil || streamFilter == "app_usage",
           let live = liveSession(db: db, rangeStart: r.start, rangeEnd: r.end),
           live.streamType == "app_usage" {
            rows = injectIntoAppRows(rows, appName: live.appName, elapsed: live.elapsedSeconds)
        }
        let streamValue: Any = streamFilter ?? NSNull()
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "stream_type": streamValue,
            "apps": rows
        ])
    }

    private static func topCategories(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 20), 500))
        guard db.hasCategoryMappings else {
            return toJSON([
                "range": ["start": r.start, "end": r.end],
                "categories": [] as [Any],
                "note": "No category mappings database found."
            ])
        }
        let rows = try db.query(
            """
            SELECT COALESCE(m.category, 'Uncategorized') AS category,
                   SUM(u.duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count,
                   COUNT(DISTINCT u.app_name) AS app_count
            FROM usage u
            LEFT JOIN cat.app_category_map m ON u.app_name = m.app_name
            WHERE u.start_time >= ? AND u.start_time < ?
            \(dedupClause(alias: "u"))
            GROUP BY category
            ORDER BY total_seconds DESC
            LIMIT ?
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end), .int(Int64(limit))]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "categories": rows
        ])
    }

    private static func sessions(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "1d", until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 500), 10000))
        var sql = """
        SELECT app_name, duration_seconds, start_time, stream_type, device_id, metadata_hash
        FROM usage
        WHERE start_time >= ? AND start_time < ?
        """
        var bindings: [SQLValue] = [.text(r.start), .text(r.end)]
        if let rawApp = args.string("app_name") {
            let app = (try? resolveAppName(rawApp, db: db)) ?? rawApp
            sql += " AND app_name = ?"
            bindings.append(.text(app))
        }
        if let stream = args.string("stream_type") {
            sql += " AND stream_type = ?"
            bindings.append(.text(stream))
        }
        sql += dedupClause()
        bindings.append(contentsOf: [.text(r.start), .text(r.end)])
        sql += " ORDER BY start_time DESC LIMIT ?"
        bindings.append(.int(Int64(limit)))
        let rows = try db.query(sql, bindings: bindings)
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "count": rows.count,
            "sessions": rows
        ])
    }

    private static func hourlyDistribution(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        var sql = """
        SELECT CAST(strftime('%H', start_time) AS INTEGER) AS hour,
               SUM(duration_seconds) AS total_seconds,
               COUNT(*) AS session_count
        FROM usage
        WHERE start_time >= ? AND start_time < ?
        """
        var bindings: [SQLValue] = [.text(r.start), .text(r.end)]
        if let rawApp = args.string("app_name") {
            let app = (try? resolveAppName(rawApp, db: db)) ?? rawApp
            sql += " AND app_name = ?"
            bindings.append(.text(app))
        }
        sql += dedupClause()
        bindings.append(contentsOf: [.text(r.start), .text(r.end)])
        sql += " GROUP BY hour ORDER BY hour"
        let rows = try db.query(sql, bindings: bindings)
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "hours": rows
        ])
    }

    private static func dailyTrend(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        var sql = """
        SELECT date(start_time) AS day,
               SUM(duration_seconds) AS total_seconds,
               COUNT(*) AS session_count
        FROM usage
        WHERE start_time >= ? AND start_time < ?
        """
        var bindings: [SQLValue] = [.text(r.start), .text(r.end)]
        if let rawApp = args.string("app_name") {
            let app = (try? resolveAppName(rawApp, db: db)) ?? rawApp
            sql += " AND app_name = ?"
            bindings.append(.text(app))
        }
        sql += dedupClause()
        bindings.append(contentsOf: [.text(r.start), .text(r.end)])
        sql += " GROUP BY day ORDER BY day"
        let rows = try db.query(sql, bindings: bindings)
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "days": rows
        ])
    }

    private static func weekdayBreakdown(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let rows = try db.query(
            """
            SELECT CAST(strftime('%w', start_time) AS INTEGER) AS weekday,
                   SUM(duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count,
                   COUNT(DISTINCT date(start_time)) AS days_observed
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY weekday
            ORDER BY weekday
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        let enriched = rows.map { row -> [String: Any] in
            var copy = row
            let total = row["total_seconds"] as? Double ?? 0
            let days = max(1, (row["days_observed"] as? Int64).map { Int($0) } ?? 1)
            copy["average_seconds"] = total / Double(days)
            return copy
        }
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "weekday_key": "0=Sunday..6=Saturday",
            "weekdays": enriched
        ])
    }

    private static func appDetail(args: Args, db: Database) throws -> String {
        let rawApp = try args.requiredString("app_name")
        let app = (try? resolveAppName(rawApp, db: db)) ?? rawApp
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let totals = try db.query(
            """
            SELECT SUM(duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count,
                   MIN(start_time) AS first_seen,
                   MAX(start_time) AS last_seen,
                   MAX(duration_seconds) AS longest_session
            FROM usage
            WHERE app_name = ? AND start_time >= ? AND start_time < ?
            \(dedupClause())
            """,
            bindings: [.text(app), .text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        let daily = try db.query(
            """
            SELECT date(start_time) AS day, SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM usage
            WHERE app_name = ? AND start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY day ORDER BY day
            """,
            bindings: [.text(app), .text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        let hourly = try db.query(
            """
            SELECT CAST(strftime('%H', start_time) AS INTEGER) AS hour, SUM(duration_seconds) AS total_seconds
            FROM usage
            WHERE app_name = ? AND start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY hour ORDER BY hour
            """,
            bindings: [.text(app), .text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        let longest = try db.query(
            """
            SELECT duration_seconds, start_time, stream_type
            FROM usage
            WHERE app_name = ? AND start_time >= ? AND start_time < ?
            \(dedupClause())
            ORDER BY duration_seconds DESC LIMIT 10
            """,
            bindings: [.text(app), .text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        var category: String = "Uncategorized"
        if db.hasCategoryMappings {
            let catRows = try db.query(
                "SELECT category FROM cat.app_category_map WHERE app_name = ?",
                bindings: [.text(app)]
            )
            if let first = catRows.first, let c = first["category"] as? String {
                category = c
            }
        }
        return toJSON([
            "app_name": app,
            "category": category,
            "range": ["start": r.start, "end": r.end],
            "summary": totals.first ?? [:],
            "daily_trend": daily,
            "hourly_distribution": hourly,
            "longest_sessions": longest
        ])
    }

    private static func streamAggregate(args: Args, db: Database, streamType: String) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 50), 500))
        let rows = try db.query(
            """
            SELECT app_name, SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM usage
            WHERE stream_type = ? AND start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY app_name ORDER BY total_seconds DESC LIMIT ?
            """,
            bindings: [.text(streamType), .text(r.start), .text(r.end), .text(r.start), .text(r.end), .int(Int64(limit))]
        )
        return toJSON([
            "stream_type": streamType,
            "range": ["start": r.start, "end": r.end],
            "apps": rows
        ])
    }

    private static func longestSessions(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 20), 500))
        var sql = """
        SELECT app_name, duration_seconds, start_time, stream_type
        FROM usage
        WHERE start_time >= ? AND start_time < ?
        """
        var bindings: [SQLValue] = [.text(r.start), .text(r.end)]
        if let s = args.string("stream_type") {
            sql += " AND stream_type = ?"
            bindings.append(.text(s))
        }
        sql += dedupClause()
        bindings.append(contentsOf: [.text(r.start), .text(r.end)])
        sql += " ORDER BY duration_seconds DESC LIMIT ?"
        bindings.append(.int(Int64(limit)))
        let rows = try db.query(sql, bindings: bindings)
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "sessions": rows
        ])
    }

    private static func sessionBuckets(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let rows = try db.query(
            """
            SELECT
              CASE
                WHEN duration_seconds < 60 THEN '<1m'
                WHEN duration_seconds < 300 THEN '1-5m'
                WHEN duration_seconds < 900 THEN '5-15m'
                WHEN duration_seconds < 1800 THEN '15-30m'
                WHEN duration_seconds < 3600 THEN '30-60m'
                ELSE '60m+'
              END AS bucket,
              COUNT(*) AS session_count,
              SUM(duration_seconds) AS total_seconds
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY bucket
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        let bucketOrder = ["<1m", "1-5m", "5-15m", "15-30m", "30-60m", "60m+"]
        let sorted = rows.sorted { lhs, rhs in
            let l = (lhs["bucket"] as? String).flatMap(bucketOrder.firstIndex(of:)) ?? 0
            let r = (rhs["bucket"] as? String).flatMap(bucketOrder.firstIndex(of:)) ?? 0
            return l < r
        }
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "buckets": sorted
        ])
    }

    private static func focusBlocks(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let minDuration = args.double("min_duration_seconds", default: 900)
        let blocks = try db.query(
            """
            SELECT date(start_time) AS day, app_name, duration_seconds, start_time, stream_type
            FROM usage
            WHERE start_time >= ? AND start_time < ? AND duration_seconds >= ?
            \(dedupClause())
            ORDER BY start_time
            """,
            bindings: [.text(r.start), .text(r.end), .double(minDuration), .text(r.start), .text(r.end)]
        )
        let byDay = try db.query(
            """
            SELECT date(start_time) AS day,
                   COUNT(*) AS focus_block_count,
                   SUM(duration_seconds) AS total_focus_seconds
            FROM usage
            WHERE start_time >= ? AND start_time < ? AND duration_seconds >= ?
            \(dedupClause())
            GROUP BY day ORDER BY day
            """,
            bindings: [.text(r.start), .text(r.end), .double(minDuration), .text(r.start), .text(r.end)]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "min_duration_seconds": minDuration,
            "by_day": byDay,
            "blocks": blocks
        ])
    }

    private static func contextSwitches(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let rows = try db.query(
            """
            SELECT date(start_time) AS day, COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ? AND stream_type = 'app_usage'
            \(dedupClause())
            GROUP BY day ORDER BY day
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "note": "Each row is one app_usage session; the count is a proxy for context switches.",
            "by_day": rows
        ])
    }

    private static func appTransitions(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 25), 500))
        let rows = try db.query(
            """
            WITH ordered AS (
              SELECT app_name, start_time,
                     LAG(app_name) OVER (PARTITION BY date(start_time) ORDER BY start_time) AS prev_app
              FROM usage
              WHERE start_time >= ? AND start_time < ? AND stream_type = 'app_usage'
              \(dedupClause())
            )
            SELECT prev_app AS from_app, app_name AS to_app, COUNT(*) AS transition_count
            FROM ordered
            WHERE prev_app IS NOT NULL AND prev_app != app_name
            GROUP BY from_app, to_app
            ORDER BY transition_count DESC
            LIMIT ?
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end), .int(Int64(limit))]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "transitions": rows
        ])
    }

    private static func devices(db: Database) throws -> String {
        let rows = try db.query(
            """
            SELECT device_id,
                   COUNT(*) AS session_count,
                   SUM(duration_seconds) AS total_seconds,
                   MIN(start_time) AS first_seen,
                   MAX(start_time) AS last_seen
            FROM usage
            WHERE device_id IS NOT NULL
            GROUP BY device_id
            ORDER BY total_seconds DESC
            """
        )
        return toJSON(["devices": rows])
    }

    private static func streamTypes(db: Database) throws -> String {
        let rows = try db.query(
            """
            SELECT stream_type,
                   COUNT(*) AS session_count,
                   SUM(duration_seconds) AS total_seconds,
                   MIN(start_time) AS first_seen,
                   MAX(start_time) AS last_seen
            FROM usage
            GROUP BY stream_type
            ORDER BY total_seconds DESC
            """
        )
        return toJSON(["stream_types": rows])
    }

    private static func categoryMappings(db: Database) throws -> String {
        guard db.hasCategoryMappings else {
            return toJSON(["mappings": [] as [Any], "note": "No category mappings database found."])
        }
        let rows = try db.query("SELECT app_name, category FROM cat.app_category_map ORDER BY app_name")
        return toJSON(["mappings": rows])
    }

    private static func comparePeriods(args: Args, db: Database) throws -> String {
        let cur = try DateRange.parse(since: args.string("current_since") ?? "7d", until: args.string("current_until"))
        let prev = try DateRange.parse(since: args.string("previous_since") ?? "14d", until: args.string("previous_until") ?? args.string("current_since") ?? "7d")
        let limit = max(1, min(args.int("limit", default: 25), 500))

        let currentTotal = try db.query(
            """
            SELECT SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            """,
            bindings: [.text(cur.start), .text(cur.end), .text(cur.start), .text(cur.end)]
        ).first ?? [:]
        let previousTotal = try db.query(
            """
            SELECT SUM(duration_seconds) AS total_seconds, COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            """,
            bindings: [.text(prev.start), .text(prev.end), .text(prev.start), .text(prev.end)]
        ).first ?? [:]

        let currentApps = try db.query(
            """
            SELECT app_name, SUM(duration_seconds) AS total_seconds
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY app_name
            """,
            bindings: [.text(cur.start), .text(cur.end), .text(cur.start), .text(cur.end)]
        )
        let previousApps = try db.query(
            """
            SELECT app_name, SUM(duration_seconds) AS total_seconds
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY app_name
            """,
            bindings: [.text(prev.start), .text(prev.end), .text(prev.start), .text(prev.end)]
        )
        var previousMap: [String: Double] = [:]
        for row in previousApps {
            if let name = row["app_name"] as? String {
                previousMap[name] = row["total_seconds"] as? Double ?? 0
            }
        }
        var deltas: [[String: Any]] = []
        for row in currentApps {
            guard let name = row["app_name"] as? String else { continue }
            let currentSeconds = row["total_seconds"] as? Double ?? 0
            let previousSeconds = previousMap[name] ?? 0
            let delta = currentSeconds - previousSeconds
            let pct: Any = previousSeconds > 0 ? (delta / previousSeconds) * 100 : NSNull()
            deltas.append([
                "app_name": name,
                "current_seconds": currentSeconds,
                "previous_seconds": previousSeconds,
                "delta_seconds": delta,
                "percent_change": pct
            ])
            previousMap.removeValue(forKey: name)
        }
        for (name, previousSeconds) in previousMap {
            deltas.append([
                "app_name": name,
                "current_seconds": 0,
                "previous_seconds": previousSeconds,
                "delta_seconds": -previousSeconds,
                "percent_change": -100.0
            ])
        }
        deltas.sort { (lhs, rhs) in
            let l = abs(lhs["delta_seconds"] as? Double ?? 0)
            let r = abs(rhs["delta_seconds"] as? Double ?? 0)
            return l > r
        }
        let trimmed = Array(deltas.prefix(limit))

        return toJSON([
            "current_range": ["start": cur.start, "end": cur.end],
            "previous_range": ["start": prev.start, "end": prev.end],
            "current_total": currentTotal,
            "previous_total": previousTotal,
            "app_deltas": trimmed
        ])
    }

    private static func heatmap(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        var sql = """
        SELECT CAST(strftime('%w', start_time) AS INTEGER) AS weekday,
               CAST(strftime('%H', start_time) AS INTEGER) AS hour,
               SUM(duration_seconds) AS total_seconds,
               COUNT(*) AS session_count
        FROM usage
        WHERE start_time >= ? AND start_time < ?
        """
        var bindings: [SQLValue] = [.text(r.start), .text(r.end)]
        if let rawApp = args.string("app_name") {
            let app = (try? resolveAppName(rawApp, db: db)) ?? rawApp
            sql += " AND app_name = ?"
            bindings.append(.text(app))
        }
        if let stream = args.string("stream_type") {
            sql += " AND stream_type = ?"
            bindings.append(.text(stream))
        }
        sql += dedupClause()
        bindings.append(contentsOf: [.text(r.start), .text(r.end)])
        sql += " GROUP BY weekday, hour ORDER BY weekday, hour"
        let rows = try db.query(sql, bindings: bindings)
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "weekday_key": "0=Sunday..6=Saturday",
            "cells": rows
        ])
    }

    private static func dailyAppBreakdown(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let topPerDay = max(1, min(args.int("top_per_day", default: 5), 50))
        let rows = try db.query(
            """
            WITH ranked AS (
              SELECT date(start_time) AS day, app_name,
                     SUM(duration_seconds) AS total_seconds,
                     COUNT(*) AS session_count,
                     ROW_NUMBER() OVER (
                       PARTITION BY date(start_time)
                       ORDER BY SUM(duration_seconds) DESC
                     ) AS rank
              FROM usage
              WHERE start_time >= ? AND start_time < ?
              \(dedupClause())
              GROUP BY day, app_name
            )
            SELECT day, app_name, total_seconds, session_count, rank
            FROM ranked
            WHERE rank <= ?
            ORDER BY day, rank
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end), .int(Int64(topPerDay))]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "top_per_day": topPerDay,
            "rows": rows
        ])
    }

    private static func categoryTrend(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        guard db.hasCategoryMappings else {
            return toJSON([
                "range": ["start": r.start, "end": r.end],
                "rows": [] as [Any],
                "note": "No category mappings database found."
            ])
        }
        let rows = try db.query(
            """
            SELECT date(u.start_time) AS day,
                   COALESCE(m.category, 'Uncategorized') AS category,
                   SUM(u.duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count
            FROM usage u
            LEFT JOIN cat.app_category_map m ON u.app_name = m.app_name
            WHERE u.start_time >= ? AND u.start_time < ?
            \(dedupClause(alias: "u"))
            GROUP BY day, category
            ORDER BY day, total_seconds DESC
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "rows": rows
        ])
    }

    private static func firstLastUse(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let streamType = args.string("stream_type") ?? "app_usage"
        let rows = try db.query(
            """
            SELECT date(start_time) AS day,
                   MIN(start_time) AS first_session,
                   MAX(start_time) AS last_session,
                   SUM(duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ? AND stream_type = ?
            \(dedupClause())
            GROUP BY day
            ORDER BY day
            """,
            bindings: [.text(r.start), .text(r.end), .text(streamType), .text(r.start), .text(r.end)]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "stream_type": streamType,
            "days": rows
        ])
    }

    private static func activeDays(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let active = try db.query(
            """
            SELECT date(start_time) AS day,
                   SUM(duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY day
            HAVING total_seconds > 0
            ORDER BY day
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )

        let activeSet = Set(active.compactMap { $0["day"] as? String })
        let calendar = Calendar.current
        var zeroDays: [String] = []
        guard let startDate = DateRange.parseDate(String(r.start.prefix(10))),
              let endDate = DateRange.parseDate(String(r.end.prefix(10))) else {
            return toJSON([
                "range": ["start": r.start, "end": r.end],
                "active_day_count": active.count,
                "active_days": active
            ])
        }
        var cursor = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        while cursor < endDay {
            let key = formatter.string(from: cursor)
            if !activeSet.contains(key) {
                zeroDays.append(key)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endDay
        }
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "active_day_count": active.count,
            "zero_day_count": zeroDays.count,
            "active_days": active,
            "zero_days": zeroDays
        ])
    }

    private static func timeOfDaySplit(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let rows = try db.query(
            """
            SELECT
              CASE
                WHEN CAST(strftime('%H', start_time) AS INTEGER) < 6 THEN 'night'
                WHEN CAST(strftime('%H', start_time) AS INTEGER) < 12 THEN 'morning'
                WHEN CAST(strftime('%H', start_time) AS INTEGER) < 17 THEN 'afternoon'
                WHEN CAST(strftime('%H', start_time) AS INTEGER) < 21 THEN 'evening'
                ELSE 'late_night'
              END AS period,
              SUM(duration_seconds) AS total_seconds,
              COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY period
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        let order = ["night", "morning", "afternoon", "evening", "late_night"]
        let sorted = rows.sorted { lhs, rhs in
            let l = (lhs["period"] as? String).flatMap(order.firstIndex(of:)) ?? 0
            let rr = (rhs["period"] as? String).flatMap(order.firstIndex(of:)) ?? 0
            return l < rr
        }
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "period_ranges": [
                "night": "00:00-05:59",
                "morning": "06:00-11:59",
                "afternoon": "12:00-16:59",
                "evening": "17:00-20:59",
                "late_night": "21:00-23:59"
            ],
            "periods": sorted
        ])
    }

    private static func weekendVsWeekday(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let rows = try db.query(
            """
            SELECT
              CASE WHEN CAST(strftime('%w', start_time) AS INTEGER) IN (0, 6)
                   THEN 'weekend' ELSE 'weekday' END AS kind,
              SUM(duration_seconds) AS total_seconds,
              COUNT(*) AS session_count,
              COUNT(DISTINCT date(start_time)) AS days_observed
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY kind
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end)]
        )
        let enriched = rows.map { row -> [String: Any] in
            var copy = row
            let total = row["total_seconds"] as? Double ?? 0
            let days = max(1, (row["days_observed"] as? Int64).map { Int($0) } ?? 1)
            copy["average_seconds_per_day"] = total / Double(days)
            return copy
        }
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "groups": enriched
        ])
    }

    private static func newApps(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 25), 500))
        let rows = try db.query(
            """
            SELECT app_name,
                   MIN(start_time) AS first_seen,
                   SUM(CASE WHEN start_time >= ? AND start_time < ? THEN duration_seconds ELSE 0 END) AS period_total_seconds,
                   SUM(CASE WHEN start_time >= ? AND start_time < ? THEN 1 ELSE 0 END) AS period_session_count
            FROM usage
            WHERE 1=1
            \(dedupClause())
            GROUP BY app_name
            HAVING first_seen >= ? AND first_seen < ?
            ORDER BY period_total_seconds DESC
            LIMIT ?
            """,
            bindings: [
                .text(r.start), .text(r.end),
                .text(r.start), .text(r.end),
                .text(r.start), .text(r.end),
                .text(r.start), .text(r.end),
                .int(Int64(limit))
            ]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "apps": rows
        ])
    }

    private static func abandonedApps(args: Args, db: Database) throws -> String {
        let cur = try DateRange.parse(
            since: args.string("current_since") ?? "7d",
            until: args.string("current_until")
        )
        let prev = try DateRange.parse(
            since: args.string("previous_since") ?? "14d",
            until: args.string("previous_until") ?? args.string("current_since") ?? "7d"
        )
        let limit = max(1, min(args.int("limit", default: 25), 500))

        let previousRows = try db.query(
            """
            SELECT app_name,
                   SUM(duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            GROUP BY app_name
            """,
            bindings: [.text(prev.start), .text(prev.end), .text(prev.start), .text(prev.end)]
        )
        let currentApps = try db.query(
            """
            SELECT DISTINCT app_name FROM usage
            WHERE start_time >= ? AND start_time < ?
            \(dedupClause())
            """,
            bindings: [.text(cur.start), .text(cur.end), .text(cur.start), .text(cur.end)]
        )
        let currentSet = Set(currentApps.compactMap { $0["app_name"] as? String })

        let abandoned = previousRows.filter { row in
            guard let name = row["app_name"] as? String else { return false }
            return !currentSet.contains(name)
        }
        .sorted { (lhs, rhs) in
            let l = lhs["total_seconds"] as? Double ?? 0
            let r = rhs["total_seconds"] as? Double ?? 0
            return l > r
        }
        .prefix(limit)

        return toJSON([
            "current_range": ["start": cur.start, "end": cur.end],
            "previous_range": ["start": prev.start, "end": prev.end],
            "abandoned_count": abandoned.count,
            "apps": Array(abandoned)
        ])
    }

    private static func usageStreaks(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "all", until: args.string("until"))
        let limit = max(1, min(args.int("limit", default: 10), 100))
        let rows = try db.query(
            """
            WITH days AS (
              SELECT DISTINCT date(start_time) AS day
              FROM usage
              WHERE start_time >= ? AND start_time < ?
              \(dedupClause())
            ),
            numbered AS (
              SELECT day,
                     julianday(day) - ROW_NUMBER() OVER (ORDER BY day) AS grp
              FROM days
            )
            SELECT MIN(day) AS start_day,
                   MAX(day) AS end_day,
                   COUNT(*) AS length
            FROM numbered
            GROUP BY grp
            ORDER BY length DESC, start_day DESC
            LIMIT ?
            """,
            bindings: [.text(r.start), .text(r.end), .text(r.start), .text(r.end), .int(Int64(limit))]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "streaks": rows
        ])
    }

    private static func pickupCount(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since"), until: args.string("until"))
        let threshold = args.double("threshold_seconds", default: 10)
        let summary = try db.query(
            """
            SELECT COUNT(*) AS pickup_count,
                   AVG(duration_seconds) AS avg_pickup_seconds,
                   SUM(duration_seconds) AS total_pickup_seconds
            FROM usage
            WHERE start_time >= ? AND start_time < ?
              AND duration_seconds < ?
              AND stream_type = 'app_usage'
            \(dedupClause())
            """,
            bindings: [.text(r.start), .text(r.end), .double(threshold), .text(r.start), .text(r.end)]
        )
        let perDay = try db.query(
            """
            SELECT date(start_time) AS day, COUNT(*) AS pickup_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?
              AND duration_seconds < ?
              AND stream_type = 'app_usage'
            \(dedupClause())
            GROUP BY day
            ORDER BY day
            """,
            bindings: [.text(r.start), .text(r.end), .double(threshold), .text(r.start), .text(r.end)]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "threshold_seconds": threshold,
            "summary": summary.first ?? [:],
            "by_day": perDay
        ])
    }

    private static func typicalDay(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "30d", until: args.string("until"))
        let rawAppFilter = args.string("app_name")
        let appFilter: String? = rawAppFilter.map { (try? resolveAppName($0, db: db)) ?? $0 }
        var filterClause = ""
        var bindings: [SQLValue] = [.text(r.start), .text(r.end)]
        if let app = appFilter {
            filterClause = " AND app_name = ?"
            bindings.append(.text(app))
        }
        bindings.append(contentsOf: [.text(r.start), .text(r.end)])

        let dayCountRow = try db.query(
            "SELECT COUNT(DISTINCT date(start_time)) AS n FROM usage WHERE start_time >= ? AND start_time < ?" + filterClause + dedupClause(),
            bindings: bindings
        )
        let dayCount = max(1, (dayCountRow.first?["n"] as? Int64).map { Int($0) } ?? 1)

        let hourRows = try db.query(
            """
            SELECT CAST(strftime('%H', start_time) AS INTEGER) AS hour,
                   SUM(duration_seconds) AS total_seconds,
                   COUNT(*) AS session_count
            FROM usage
            WHERE start_time >= ? AND start_time < ?\(filterClause)
            \(dedupClause())
            GROUP BY hour
            ORDER BY hour
            """,
            bindings: bindings
        )
        let enriched = hourRows.map { row -> [String: Any] in
            var copy = row
            let total = row["total_seconds"] as? Double ?? 0
            copy["average_seconds"] = total / Double(dayCount)
            return copy
        }
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "app_name": (appFilter as Any?) ?? NSNull(),
            "days_observed": dayCount,
            "hours": enriched
        ])
    }

    private static func metadataHashBreakdown(args: Args, db: Database) throws -> String {
        let r = try DateRange.parse(since: args.string("since") ?? "all", until: args.string("until"))
        let rows = try db.query(
            """
            SELECT COALESCE(metadata_hash, '(null)') AS metadata_hash,
                   COUNT(*) AS session_count,
                   SUM(duration_seconds) AS total_seconds,
                   MIN(start_time) AS first_seen,
                   MAX(start_time) AS last_seen
            FROM usage
            WHERE start_time >= ? AND start_time < ?
            GROUP BY metadata_hash
            ORDER BY total_seconds DESC
            """,
            bindings: [.text(r.start), .text(r.end)]
        )
        return toJSON([
            "range": ["start": r.start, "end": r.end],
            "sources": rows
        ])
    }

    private static func rawQuery(args: Args, db: Database) throws -> String {
        let sql = try args.requiredString("sql")
        let rows = try db.queryReadOnlyRaw(sql)
        return toJSON([
            "row_count": rows.count,
            "rows": rows
        ])
    }

    // MARK: - JSON helper

    private static func toJSON(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        ),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to serialize result\"}"
        }
        return string
    }
}
