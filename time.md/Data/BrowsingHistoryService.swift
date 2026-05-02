import Foundation
import SQLite3

// MARK: - Public protocol

protocol BrowsingHistoryServing: Sendable {
    func fetchVisits(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) async throws -> [BrowsingVisit]

    func fetchTopDomains(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [DomainSummary]

    func fetchDailyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailyVisitCount]

    func fetchHourlyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [HourlyVisitCount]

    func fetchPagesForDomain(
        domain: String,
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [PageSummary]

    func availableBrowsers() -> [BrowserSource]
}

// MARK: - Errors

enum BrowsingHistoryError: LocalizedError {
    case sqlite(message: String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            return "SQLite error: \(message)"
        }
    }
}

// MARK: - Implementation
//
// Reads web browsing data from the app's own `screentime.db` (rows with
// `stream_type = 'web_usage'`). Each row represents a tab session sampled by
// `BrowserTabSampler`; `app_name` holds the domain.

final class SQLiteBrowsingHistoryService: BrowsingHistoryServing, @unchecked Sendable {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// No-op now that we read from our own DB; kept so call sites in
    /// `time.mdApp.swift` don't need to change.
    func prefetchDatabases() {}

    // MARK: - Available browsers

    /// Per-browser data isn't tracked yet (only domains via AppleScript), so
    /// the UI shows a single "All" segment.
    func availableBrowsers() -> [BrowserSource] { [.all] }

    // MARK: - Connection

    private func openReadOnly() throws -> OpaquePointer {
        let url = try HistoryStore.databaseURL()
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let db = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let h = handle { sqlite3_close(h) }
            throw BrowsingHistoryError.sqlite(message: msg)
        }
        sqlite3_busy_timeout(db, 2000)
        return db
    }

    private func startISO(_ date: Date) -> String { Self.dateFormatter.string(from: date) }
    private func date(fromISO s: String) -> Date { Self.dateFormatter.date(from: s) ?? Date.distantPast }

    // MARK: - Fetch visits

    func fetchVisits(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) async throws -> [BrowsingVisit] {
        try await Task.detached(priority: .userInitiated) {
            let db = try self.openReadOnly()
            defer { sqlite3_close(db) }

            var sql = """
            SELECT app_name, start_time, duration_seconds
            FROM usage
            WHERE stream_type = 'web_usage'
              AND start_time >= ?
              AND start_time < ?
            """
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sql += " AND app_name LIKE ?"
            }
            sql += " ORDER BY start_time DESC LIMIT ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                throw BrowsingHistoryError.sqlite(message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(s) }

            var idx: Int32 = 1
            sqlite3_bind_text(s, idx, self.startISO(startDate), -1, Self.sqliteTransient); idx += 1
            sqlite3_bind_text(s, idx, self.startISO(endDate), -1, Self.sqliteTransient); idx += 1
            if !trimmed.isEmpty {
                sqlite3_bind_text(s, idx, "%\(trimmed)%", -1, Self.sqliteTransient); idx += 1
            }
            sqlite3_bind_int64(s, idx, Int64(limit))

            var rows: [BrowsingVisit] = []
            rows.reserveCapacity(min(limit, 1000))
            while sqlite3_step(s) == SQLITE_ROW {
                guard let cName = sqlite3_column_text(s, 0),
                      let cStart = sqlite3_column_text(s, 1) else { continue }
                let domain = String(cString: cName)
                let startStr = String(cString: cStart)
                let duration = sqlite3_column_double(s, 2)
                let when = self.date(fromISO: startStr)
                rows.append(BrowsingVisit(
                    id: "\(startStr)|\(domain)",
                    url: "https://\(domain)/",
                    title: domain,
                    domain: domain,
                    visitTime: when,
                    durationSeconds: duration,
                    browser: .all
                ))
            }
            return rows
        }.value
    }

    // MARK: - Fetch top domains

    func fetchTopDomains(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [DomainSummary] {
        try await Task.detached(priority: .userInitiated) {
            let db = try self.openReadOnly()
            defer { sqlite3_close(db) }

            let sql = """
            SELECT app_name,
                   COUNT(*)            AS visits,
                   SUM(duration_seconds) AS duration,
                   MAX(start_time)     AS last_visit
            FROM usage
            WHERE stream_type = 'web_usage'
              AND start_time >= ?
              AND start_time < ?
            GROUP BY app_name
            ORDER BY visits DESC
            LIMIT ?
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                throw BrowsingHistoryError.sqlite(message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(s) }

            sqlite3_bind_text(s, 1, self.startISO(startDate), -1, Self.sqliteTransient)
            sqlite3_bind_text(s, 2, self.startISO(endDate), -1, Self.sqliteTransient)
            sqlite3_bind_int64(s, 3, Int64(limit))

            var rows: [DomainSummary] = []
            while sqlite3_step(s) == SQLITE_ROW {
                guard let cName = sqlite3_column_text(s, 0),
                      let cLast = sqlite3_column_text(s, 3) else { continue }
                let domain = String(cString: cName)
                let visits = Int(sqlite3_column_int64(s, 1))
                let duration = sqlite3_column_double(s, 2)
                let last = self.date(fromISO: String(cString: cLast))
                rows.append(DomainSummary(
                    domain: domain,
                    visitCount: visits,
                    totalDurationSeconds: duration,
                    lastVisitTime: last
                ))
            }
            return rows
        }.value
    }

    // MARK: - Fetch daily visit counts

    func fetchDailyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailyVisitCount] {
        try await Task.detached(priority: .userInitiated) {
            let db = try self.openReadOnly()
            defer { sqlite3_close(db) }

            let sql = """
            SELECT substr(start_time, 1, 10) AS day, COUNT(*) AS visits
            FROM usage
            WHERE stream_type = 'web_usage'
              AND start_time >= ?
              AND start_time < ?
            GROUP BY day
            ORDER BY day
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                throw BrowsingHistoryError.sqlite(message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(s) }

            sqlite3_bind_text(s, 1, self.startISO(startDate), -1, Self.sqliteTransient)
            sqlite3_bind_text(s, 2, self.startISO(endDate), -1, Self.sqliteTransient)

            let dayFormatter: DateFormatter = {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = .current
                f.dateFormat = "yyyy-MM-dd"
                return f
            }()

            var rows: [DailyVisitCount] = []
            while sqlite3_step(s) == SQLITE_ROW {
                guard let cDay = sqlite3_column_text(s, 0) else { continue }
                let dayStr = String(cString: cDay)
                guard let day = dayFormatter.date(from: dayStr) else { continue }
                let count = Int(sqlite3_column_int64(s, 1))
                rows.append(DailyVisitCount(date: day, visitCount: count))
            }
            return rows
        }.value
    }

    // MARK: - Fetch hourly visit counts

    func fetchHourlyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [HourlyVisitCount] {
        try await Task.detached(priority: .userInitiated) {
            let db = try self.openReadOnly()
            defer { sqlite3_close(db) }

            let sql = """
            SELECT CAST(substr(start_time, 12, 2) AS INTEGER) AS hr, COUNT(*) AS visits
            FROM usage
            WHERE stream_type = 'web_usage'
              AND start_time >= ?
              AND start_time < ?
            GROUP BY hr
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                throw BrowsingHistoryError.sqlite(message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(s) }

            sqlite3_bind_text(s, 1, self.startISO(startDate), -1, Self.sqliteTransient)
            sqlite3_bind_text(s, 2, self.startISO(endDate), -1, Self.sqliteTransient)

            var counts: [Int: Int] = [:]
            while sqlite3_step(s) == SQLITE_ROW {
                let hr = Int(sqlite3_column_int64(s, 0))
                let visits = Int(sqlite3_column_int64(s, 1))
                counts[hr] = visits
            }
            return (0..<24).map { HourlyVisitCount(hour: $0, visitCount: counts[$0] ?? 0) }
        }.value
    }

    // MARK: - Pages for domain

    /// We only have domain-level data — there are no per-path rows. The
    /// drill-down returns a single `PageSummary` per domain whose visits are
    /// the underlying sample rows.
    func fetchPagesForDomain(
        domain: String,
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [PageSummary] {
        try await Task.detached(priority: .userInitiated) {
            let db = try self.openReadOnly()
            defer { sqlite3_close(db) }

            let sql = """
            SELECT start_time, duration_seconds
            FROM usage
            WHERE stream_type = 'web_usage'
              AND app_name = ?
              AND start_time >= ?
              AND start_time < ?
            ORDER BY start_time DESC
            LIMIT ?
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                throw BrowsingHistoryError.sqlite(message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(s) }

            sqlite3_bind_text(s, 1, domain, -1, Self.sqliteTransient)
            sqlite3_bind_text(s, 2, self.startISO(startDate), -1, Self.sqliteTransient)
            sqlite3_bind_text(s, 3, self.startISO(endDate), -1, Self.sqliteTransient)
            sqlite3_bind_int64(s, 4, Int64(limit))

            var visits: [PageVisit] = []
            while sqlite3_step(s) == SQLITE_ROW {
                guard let cStart = sqlite3_column_text(s, 0) else { continue }
                let startStr = String(cString: cStart)
                let duration = sqlite3_column_double(s, 1)
                let when = self.date(fromISO: startStr)
                visits.append(PageVisit(
                    id: "\(startStr)|\(domain)",
                    url: "https://\(domain)/",
                    path: "/",
                    title: domain,
                    visitTime: when,
                    durationSeconds: duration,
                    browser: .all
                ))
            }

            guard let last = visits.first?.visitTime else { return [] }
            let total = visits.compactMap(\.durationSeconds).reduce(0, +)
            return [PageSummary(
                path: "/",
                title: domain,
                visitCount: visits.count,
                visits: visits,
                lastVisitTime: last,
                totalDurationSeconds: total
            )]
        }.value
    }
}
