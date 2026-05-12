import Foundation
import SQLite3

/// Local, opt-in archive for browser history snapshots.
///
/// When enabled, time.md copies browser visit rows into its own local database so
/// the Web History view can keep showing visits even after the source browser
/// history has been cleared. Nothing leaves this Mac.
enum WebHistoryArchiveStore {
    nonisolated static let enabledKey = "webHistoryPersistenceEnabled"

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    nonisolated static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    static func upsert(_ visits: [BrowsingVisit]) async throws {
        guard !visits.isEmpty else { return }
        try await Task.detached(priority: .utility) {
            try Self.upsertSync(visits)
        }.value
    }

    static func fetchVisits(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) async throws -> [BrowsingVisit] {
        try await Task.detached(priority: .userInitiated) {
            try Self.fetchVisitsSync(
                browser: browser,
                startDate: startDate,
                endDate: endDate,
                searchText: searchText,
                limit: limit
            )
        }.value
    }

    static func fetchTopDomains(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [DomainSummary] {
        try await Task.detached(priority: .userInitiated) {
            try Self.fetchTopDomainsSync(browser: browser, startDate: startDate, endDate: endDate, limit: limit)
        }.value
    }

    static func fetchDailyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailyVisitCount] {
        try await Task.detached(priority: .userInitiated) {
            try Self.fetchDailyVisitCountsSync(browser: browser, startDate: startDate, endDate: endDate)
        }.value
    }

    static func fetchHourlyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [HourlyVisitCount] {
        try await Task.detached(priority: .userInitiated) {
            try Self.fetchHourlyVisitCountsSync(browser: browser, startDate: startDate, endDate: endDate)
        }.value
    }

    static func fetchPagesForDomain(
        domain: String,
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [PageSummary] {
        try await Task.detached(priority: .userInitiated) {
            try Self.fetchPagesForDomainSync(
                domain: domain,
                browser: browser,
                startDate: startDate,
                endDate: endDate,
                limit: limit
            )
        }.value
    }

    static func deleteAll() async throws {
        try await Task.detached(priority: .utility) {
            let db = try Self.openReadWrite()
            defer { sqlite3_close(db) }

            guard sqlite3_exec(db, "DELETE FROM web_history_visits", nil, nil, nil) == SQLITE_OK else {
                throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
            }
        }.value
    }

    static func archivedBrowsersSync() throws -> [BrowserSource] {
        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        let sql = "SELECT DISTINCT browser FROM web_history_visits ORDER BY browser"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var browsers: [BrowserSource] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = columnText(statement, 0), let browser = BrowserSource(rawValue: raw) else { continue }
            browsers.append(browser)
        }
        return browsers
    }

    // MARK: - Sync storage

    nonisolated private static func upsertSync(_ visits: [BrowsingVisit]) throws {
        let db = try openReadWrite()
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
        }

        do {
            let sql = """
            INSERT INTO web_history_visits
                (browser, url, title, domain, visit_time, duration_seconds, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(browser, visit_time, url) DO UPDATE SET
                title = excluded.title,
                domain = excluded.domain,
                duration_seconds = COALESCE(excluded.duration_seconds, web_history_visits.duration_seconds),
                last_seen_at = excluded.last_seen_at
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            let now = Date().timeIntervalSince1970
            for visit in visits {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)

                bindText(statement, 1, visit.browser.rawValue)
                bindText(statement, 2, visit.url)
                bindText(statement, 3, visit.title)
                bindText(statement, 4, visit.domain)
                sqlite3_bind_double(statement, 5, visit.visitTime.timeIntervalSince1970)
                if let duration = visit.durationSeconds {
                    sqlite3_bind_double(statement, 6, duration)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                sqlite3_bind_double(statement, 7, now)
                sqlite3_bind_double(statement, 8, now)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
                }
            }

            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
            }
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    // MARK: - Query helpers

    nonisolated private static func fetchVisitsSync(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) throws -> [BrowsingVisit] {
        guard limit > 0 else { return [] }

        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var sql = """
        SELECT browser, url, title, domain, visit_time, duration_seconds
        FROM web_history_visits
        WHERE visit_time >= ? AND visit_time <= ?
        """
        if browser != .all {
            sql += " AND browser = ?"
        }
        if !trimmed.isEmpty {
            sql += " AND (url LIKE ? OR title LIKE ? OR domain LIKE ?)"
        }
        sql += " ORDER BY visit_time DESC LIMIT ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var idx: Int32 = 1
        sqlite3_bind_double(statement, idx, startDate.timeIntervalSince1970); idx += 1
        sqlite3_bind_double(statement, idx, endDate.timeIntervalSince1970); idx += 1
        if browser != .all {
            bindText(statement, idx, browser.rawValue); idx += 1
        }
        if !trimmed.isEmpty {
            let pattern = "%\(trimmed)%"
            bindText(statement, idx, pattern); idx += 1
            bindText(statement, idx, pattern); idx += 1
            bindText(statement, idx, pattern); idx += 1
        }
        sqlite3_bind_int(statement, idx, Int32(min(limit, Int(Int32.max))))

        var visits: [BrowsingVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            visits.append(makeBrowsingVisit(statement: statement, idPrefix: "archive"))
        }
        return visits
    }

    nonisolated private static func fetchTopDomainsSync(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) throws -> [DomainSummary] {
        guard limit > 0 else { return [] }

        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        var sql = """
        SELECT domain, COUNT(*) AS cnt, SUM(duration_seconds) AS total_duration, MAX(visit_time) AS last_visit
        FROM web_history_visits
        WHERE visit_time >= ? AND visit_time <= ? AND domain != ''
        """
        if browser != .all {
            sql += " AND browser = ?"
        }
        sql += " GROUP BY domain ORDER BY cnt DESC LIMIT ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var idx: Int32 = 1
        sqlite3_bind_double(statement, idx, startDate.timeIntervalSince1970); idx += 1
        sqlite3_bind_double(statement, idx, endDate.timeIntervalSince1970); idx += 1
        if browser != .all {
            bindText(statement, idx, browser.rawValue); idx += 1
        }
        sqlite3_bind_int(statement, idx, Int32(min(limit, Int(Int32.max))))

        var domains: [DomainSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let domain = columnText(statement, 0) else { continue }
            let count = Int(sqlite3_column_int64(statement, 1))
            let duration = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 2)
            let lastVisit = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            domains.append(DomainSummary(
                domain: domain,
                visitCount: count,
                totalDurationSeconds: duration,
                lastVisitTime: lastVisit
            ))
        }
        return domains
    }

    nonisolated private static func fetchDailyVisitCountsSync(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) throws -> [DailyVisitCount] {
        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        var sql = """
        SELECT DATE(visit_time, 'unixepoch', 'localtime') AS day, COUNT(*) AS cnt
        FROM web_history_visits
        WHERE visit_time >= ? AND visit_time <= ?
        """
        if browser != .all {
            sql += " AND browser = ?"
        }
        sql += " GROUP BY day ORDER BY day"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var idx: Int32 = 1
        sqlite3_bind_double(statement, idx, startDate.timeIntervalSince1970); idx += 1
        sqlite3_bind_double(statement, idx, endDate.timeIntervalSince1970); idx += 1
        if browser != .all {
            bindText(statement, idx, browser.rawValue)
        }

        let formatter = dayFormatter()
        var counts: [DailyVisitCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let day = columnText(statement, 0), let date = formatter.date(from: day) else { continue }
            counts.append(DailyVisitCount(date: date, visitCount: Int(sqlite3_column_int64(statement, 1))))
        }
        return counts
    }

    nonisolated private static func fetchHourlyVisitCountsSync(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) throws -> [HourlyVisitCount] {
        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        var sql = """
        SELECT CAST(STRFTIME('%H', visit_time, 'unixepoch', 'localtime') AS INTEGER) AS hr, COUNT(*) AS cnt
        FROM web_history_visits
        WHERE visit_time >= ? AND visit_time <= ?
        """
        if browser != .all {
            sql += " AND browser = ?"
        }
        sql += " GROUP BY hr ORDER BY hr"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var idx: Int32 = 1
        sqlite3_bind_double(statement, idx, startDate.timeIntervalSince1970); idx += 1
        sqlite3_bind_double(statement, idx, endDate.timeIntervalSince1970); idx += 1
        if browser != .all {
            bindText(statement, idx, browser.rawValue)
        }

        var merged: [Int: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            merged[Int(sqlite3_column_int64(statement, 0))] = Int(sqlite3_column_int64(statement, 1))
        }

        return (0..<24).map { hour in
            HourlyVisitCount(hour: hour, visitCount: merged[hour] ?? 0)
        }
    }

    nonisolated private static func fetchPagesForDomainSync(
        domain: String,
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) throws -> [PageSummary] {
        guard limit > 0 else { return [] }

        let db = try openReadOnly()
        defer { sqlite3_close(db) }

        let domainLower = domain.lowercased()
        let wwwDomainLower = domainLower.hasPrefix("www.") ? String(domainLower.dropFirst(4)) : "www.\(domainLower)"

        var sql = """
        SELECT browser, url, title, domain, visit_time, duration_seconds
        FROM web_history_visits
        WHERE visit_time >= ? AND visit_time <= ?
          AND (LOWER(domain) = ? OR LOWER(domain) = ?)
        """
        if browser != .all {
            sql += " AND browser = ?"
        }
        sql += " ORDER BY visit_time DESC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw BrowsingHistoryError.sqlite(path: "web_history_visits", message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var idx: Int32 = 1
        sqlite3_bind_double(statement, idx, startDate.timeIntervalSince1970); idx += 1
        sqlite3_bind_double(statement, idx, endDate.timeIntervalSince1970); idx += 1
        bindText(statement, idx, domainLower); idx += 1
        bindText(statement, idx, wwwDomainLower); idx += 1
        if browser != .all {
            bindText(statement, idx, browser.rawValue)
        }

        var pathGroups: [String: [PageVisit]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let visit = makePageVisit(statement: statement, idPrefix: "archive-page")
            pathGroups[visit.path, default: []].append(visit)
        }

        return pathGroups.map { path, visits in
            let sortedVisits = visits.sorted { $0.visitTime > $1.visitTime }
            let totalDuration = sortedVisits.compactMap(\.durationSeconds).reduce(0, +)
            return PageSummary(
                path: path,
                title: sortedVisits.first?.title ?? path,
                visitCount: sortedVisits.count,
                visits: sortedVisits,
                lastVisitTime: sortedVisits.first?.visitTime ?? Date.distantPast,
                totalDurationSeconds: totalDuration > 0 ? totalDuration : nil
            )
        }
        .sorted { $0.visitCount > $1.visitCount }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: - SQLite helpers

    nonisolated private static func openReadWrite() throws -> OpaquePointer {
        let url = try HistoryStore.databaseURL()
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open archive database"
            if let handle { sqlite3_close(handle) }
            throw BrowsingHistoryError.sqlite(path: url.path, message: message)
        }
        sqlite3_busy_timeout(db, 5000)
        return db
    }

    nonisolated private static func openReadOnly() throws -> OpaquePointer {
        let url = try HistoryStore.databaseURL()
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open archive database"
            if let handle { sqlite3_close(handle) }
            throw BrowsingHistoryError.sqlite(path: url.path, message: message)
        }
        sqlite3_busy_timeout(db, 5000)
        return db
    }

    nonisolated private static func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    nonisolated private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cStr)
    }

    nonisolated private static func makeBrowsingVisit(statement: OpaquePointer, idPrefix: String) -> BrowsingVisit {
        let browserRaw = columnText(statement, 0) ?? BrowserSource.all.rawValue
        let browser = BrowserSource(rawValue: browserRaw) ?? .all
        let url = columnText(statement, 1) ?? ""
        let title = columnText(statement, 2) ?? ""
        let domain = columnText(statement, 3) ?? ""
        let visitTimestamp = sqlite3_column_double(statement, 4)
        let duration = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5)
        let visitTime = Date(timeIntervalSince1970: visitTimestamp)

        return BrowsingVisit(
            id: "\(idPrefix)-\(browserRaw)-\(visitTimestamp)-\(url.hashValue)",
            url: url,
            title: title.isEmpty ? domain : title,
            domain: domain,
            visitTime: visitTime,
            durationSeconds: duration,
            browser: browser
        )
    }

    nonisolated private static func makePageVisit(statement: OpaquePointer, idPrefix: String) -> PageVisit {
        let visit = makeBrowsingVisit(statement: statement, idPrefix: idPrefix)
        let path = extractPath(from: visit.url)
        return PageVisit(
            id: "\(idPrefix)-\(visit.browser.rawValue)-\(visit.visitTime.timeIntervalSince1970)-\(visit.url.hashValue)",
            url: visit.url,
            path: path,
            title: visit.title.isEmpty ? path : visit.title,
            visitTime: visit.visitTime,
            durationSeconds: visit.durationSeconds,
            browser: visit.browser
        )
    }

    nonisolated private static func extractPath(from urlString: String) -> String {
        guard let components = URLComponents(string: urlString) else { return "/" }
        var path = components.path.isEmpty ? "/" : components.path
        if let query = components.query, !query.isEmpty {
            path += "?\(query)"
        }
        return path
    }

    nonisolated private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

/// Periodically snapshots recent browser visits while persistence is enabled.
final class WebHistoryArchiveScheduler: @unchecked Sendable {
    static let shared = WebHistoryArchiveScheduler()

    private let queue = DispatchQueue(label: "time.md.web-history-archive-scheduler")
    private var timer: DispatchSourceTimer?
    private var isSyncing = false

    private init() {}

    func updateForCurrentSettings() {
        if WebHistoryArchiveStore.isEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 30, repeating: 15 * 60)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                guard WebHistoryArchiveStore.isEnabled else {
                    self.stop()
                    return
                }
                guard !self.isSyncing else { return }

                self.isSyncing = true
                Task.detached(priority: .utility) { [weak self] in
                    await SQLiteBrowsingHistoryService().snapshotRecentHistoryForPersistence(days: 7)
                    self?.queue.async {
                        self?.isSyncing = false
                    }
                }
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.isSyncing = false
        }
    }
}
