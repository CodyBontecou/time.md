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

    func availableBrowsers() -> [BrowserSource]
}

// MARK: - Errors

enum BrowsingHistoryError: LocalizedError {
    case databaseNotFound(browser: String)
    case permissionDenied(path: String)
    case sqlite(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let browser):
            return "\(browser) history database not found."
        case .permissionDenied(let path):
            return "Permission denied reading \(path). Grant Full Disk Access in System Settings → Privacy & Security."
        case .sqlite(let path, let message):
            return "SQLite error (\(path)): \(message)"
        }
    }
}

// MARK: - Implementation

final class SQLiteBrowsingHistoryService: BrowsingHistoryServing, @unchecked Sendable {
    // Time epoch offsets
    private static let appleEpochOffset: Double = 978_307_200          // seconds: 2001-01-01 → Unix
    private static let chromiumEpochOffset: Double = 11_644_473_600    // seconds: 1601-01-01 → Unix
    private static let chromiumMicrosPerSecond: Double = 1_000_000

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Database paths

    private static var safariHistoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Safari/History.db")
    }

    private static var chromeHistoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/History")
    }

    // MARK: - Available browsers

    func availableBrowsers() -> [BrowserSource] {
        var sources: [BrowserSource] = []
        if FileManager.default.fileExists(atPath: Self.safariHistoryURL.path) {
            sources.append(.safari)
        }
        if FileManager.default.fileExists(atPath: Self.chromeHistoryURL.path) {
            sources.append(.chrome)
        }
        if sources.count > 1 {
            sources.insert(.all, at: 0)
        }
        return sources
    }

    // MARK: - Fetch visits

    func fetchVisits(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) async throws -> [BrowsingVisit] {
        var allVisits: [BrowsingVisit] = []

        let browsers = resolveBrowsers(browser)

        for b in browsers {
            let visits = try await fetchVisitsFromBrowser(
                b, startDate: startDate, endDate: endDate,
                searchText: searchText, limit: limit
            )
            allVisits.append(contentsOf: visits)
        }

        // Sort by visit time descending, then trim to limit
        allVisits.sort { $0.visitTime > $1.visitTime }
        if allVisits.count > limit {
            allVisits = Array(allVisits.prefix(limit))
        }
        return allVisits
    }

    // MARK: - Fetch top domains

    func fetchTopDomains(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [DomainSummary] {
        var merged: [String: (count: Int, duration: Double?, lastVisit: Date)] = [:]

        let browsers = resolveBrowsers(browser)

        for b in browsers {
            let domains = try await fetchTopDomainsFromBrowser(
                b, startDate: startDate, endDate: endDate, limit: 500
            )
            for d in domains {
                if var existing = merged[d.domain] {
                    existing.count += d.visitCount
                    if let newDur = d.totalDurationSeconds {
                        existing.duration = (existing.duration ?? 0) + newDur
                    }
                    if d.lastVisitTime > existing.lastVisit {
                        existing.lastVisit = d.lastVisitTime
                    }
                    merged[d.domain] = existing
                } else {
                    merged[d.domain] = (d.visitCount, d.totalDurationSeconds, d.lastVisitTime)
                }
            }
        }

        return merged.map { domain, values in
            DomainSummary(
                domain: domain,
                visitCount: values.count,
                totalDurationSeconds: values.duration,
                lastVisitTime: values.lastVisit
            )
        }
        .sorted { $0.visitCount > $1.visitCount }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: - Fetch daily visit counts

    func fetchDailyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailyVisitCount] {
        var merged: [String: Int] = [:]
        let browsers = resolveBrowsers(browser)
        let formatter = Self.dayFormatter()

        for b in browsers {
            let counts = try await fetchDailyCountsFromBrowser(b, startDate: startDate, endDate: endDate)
            for c in counts {
                let key = formatter.string(from: c.date)
                merged[key, default: 0] += c.visitCount
            }
        }

        return merged.compactMap { key, count in
            guard let date = formatter.date(from: key) else { return nil }
            return DailyVisitCount(date: date, visitCount: count)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Fetch hourly visit counts

    func fetchHourlyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [HourlyVisitCount] {
        var merged: [Int: Int] = [:]
        let browsers = resolveBrowsers(browser)

        for b in browsers {
            let counts = try await fetchHourlyCountsFromBrowser(b, startDate: startDate, endDate: endDate)
            for c in counts {
                merged[c.hour, default: 0] += c.visitCount
            }
        }

        return (0..<24).map { hour in
            HourlyVisitCount(hour: hour, visitCount: merged[hour] ?? 0)
        }
    }

    // MARK: - Helpers

    private func resolveBrowsers(_ source: BrowserSource) -> [BrowserSource] {
        switch source {
        case .all:
            var result: [BrowserSource] = []
            if FileManager.default.fileExists(atPath: Self.safariHistoryURL.path) { result.append(.safari) }
            if FileManager.default.fileExists(atPath: Self.chromeHistoryURL.path) { result.append(.chrome) }
            return result
        case .safari, .chrome:
            return [source]
        }
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    // MARK: - Domain extraction

    private static func extractDomain(from urlString: String) -> String {
        guard let comps = URLComponents(string: urlString), let host = comps.host else {
            // Fallback: try simple extraction
            if let range = urlString.range(of: "://") {
                let after = urlString[range.upperBound...]
                let host = after.prefix(while: { $0 != "/" && $0 != ":" && $0 != "?" })
                return String(host)
            }
            return urlString
        }
        // Strip www. prefix
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    // MARK: - Open database (copies to temp to avoid locks)

    private func openDatabase(for browser: BrowserSource) throws -> (db: OpaquePointer, tempURL: URL) {
        let sourceURL: URL
        switch browser {
        case .safari:
            sourceURL = Self.safariHistoryURL
        case .chrome:
            sourceURL = Self.chromeHistoryURL
        case .all:
            fatalError("Should not call openDatabase with .all")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw BrowsingHistoryError.databaseNotFound(browser: browser.rawValue)
        }

        // Copy to temp to avoid locking the browser's live database
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Timeprint-BH-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempDB = tempDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Use sqlite3_backup for a consistent snapshot
        var sourceHandle: OpaquePointer?
        let srcResult = sqlite3_open_v2(sourceURL.path, &sourceHandle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard srcResult == SQLITE_OK, let srcDB = sourceHandle else {
            let code = srcResult
            if let sourceHandle { sqlite3_close(sourceHandle) }
            if code == SQLITE_CANTOPEN || code == SQLITE_PERM || code == SQLITE_AUTH {
                throw BrowsingHistoryError.permissionDenied(path: sourceURL.path)
            }
            throw BrowsingHistoryError.sqlite(path: sourceURL.path, message: "Cannot open source database (code \(code))")
        }
        defer { sqlite3_close(srcDB) }

        var destHandle: OpaquePointer?
        let dstResult = sqlite3_open_v2(
            tempDB.path, &destHandle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard dstResult == SQLITE_OK, let dstDB = destHandle else {
            if let destHandle { sqlite3_close(destHandle) }
            throw BrowsingHistoryError.sqlite(path: tempDB.path, message: "Cannot create temp database")
        }

        guard let backup = sqlite3_backup_init(dstDB, "main", srcDB, "main") else {
            sqlite3_close(dstDB)
            throw BrowsingHistoryError.sqlite(path: sourceURL.path, message: "Backup init failed")
        }

        var step: Int32 = SQLITE_OK
        var retries = 0
        repeat {
            step = sqlite3_backup_step(backup, -1)
            if step == SQLITE_BUSY || step == SQLITE_LOCKED {
                retries += 1
                if retries > 100 { break }
                sqlite3_sleep(25)
            }
        } while step == SQLITE_BUSY || step == SQLITE_LOCKED

        let finish = sqlite3_backup_finish(backup)

        guard step == SQLITE_DONE, finish == SQLITE_OK else {
            sqlite3_close(dstDB)
            throw BrowsingHistoryError.sqlite(path: sourceURL.path, message: "Backup failed (step=\(step), finish=\(finish))")
        }

        return (dstDB, tempDB)
    }

    private func closeDatabase(_ db: OpaquePointer, tempURL: URL) {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    // MARK: - Safari queries

    private func fetchVisitsFromSafari(
        startDate: Date, endDate: Date, searchText: String, limit: Int
    ) throws -> [BrowsingVisit] {
        let (db, tempURL) = try openDatabase(for: .safari)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startApple = startDate.timeIntervalSince1970 - Self.appleEpochOffset
        let endApple = endDate.timeIntervalSince1970 - Self.appleEpochOffset

        var sql = """
        SELECT hi.url, hv.title, hv.visit_time, hi.domain_expansion
        FROM history_visits hv
        JOIN history_items hi ON hi.id = hv.history_item
        WHERE hv.visit_time >= ?1 AND hv.visit_time <= ?2
          AND hv.load_successful = 1
        """
        if !searchText.isEmpty {
            sql += " AND (hi.url LIKE ?3 OR hv.title LIKE ?3 OR hi.domain_expansion LIKE ?3)"
        }
        sql += " ORDER BY hv.visit_time DESC LIMIT ?4"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startApple)
        sqlite3_bind_double(statement, 2, endApple)
        if !searchText.isEmpty {
            let pattern = "%\(searchText)%"
            sqlite3_bind_text(statement, 3, pattern, -1, Self.sqliteTransient)
            sqlite3_bind_int(statement, 4, Int32(limit))
        } else {
            sqlite3_bind_int(statement, 4, Int32(limit))
        }

        var visits: [BrowsingVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = Self.columnText(statement, 0) ?? ""
            let title = Self.columnText(statement, 1) ?? ""
            let visitTime = sqlite3_column_double(statement, 2)
            let domainExpansion = Self.columnText(statement, 3) ?? ""

            let date = Date(timeIntervalSince1970: visitTime + Self.appleEpochOffset)
            let domain = domainExpansion.isEmpty ? Self.extractDomain(from: url) : domainExpansion

            visits.append(BrowsingVisit(
                id: "safari-\(visitTime)-\(url.hashValue)",
                url: url,
                title: title.isEmpty ? Self.extractDomain(from: url) : title,
                domain: domain,
                visitTime: date,
                durationSeconds: nil,
                browser: .safari
            ))
        }
        return visits
    }

    // MARK: - Chrome queries

    private func fetchVisitsFromChrome(
        startDate: Date, endDate: Date, searchText: String, limit: Int
    ) throws -> [BrowsingVisit] {
        let (db, tempURL) = try openDatabase(for: .chrome)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startChrome = (startDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond
        let endChrome = (endDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond

        var sql = """
        SELECT u.url, u.title, v.visit_time, v.visit_duration
        FROM visits v
        JOIN urls u ON u.id = v.url
        WHERE v.visit_time >= ?1 AND v.visit_time <= ?2
        """
        if !searchText.isEmpty {
            sql += " AND (u.url LIKE ?3 OR u.title LIKE ?3)"
        }
        sql += " ORDER BY v.visit_time DESC LIMIT ?4"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startChrome)
        sqlite3_bind_double(statement, 2, endChrome)
        if !searchText.isEmpty {
            let pattern = "%\(searchText)%"
            sqlite3_bind_text(statement, 3, pattern, -1, Self.sqliteTransient)
            sqlite3_bind_int64(statement, 4, Int64(limit))
        } else {
            sqlite3_bind_int64(statement, 4, Int64(limit))
        }

        var visits: [BrowsingVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = Self.columnText(statement, 0) ?? ""
            let title = Self.columnText(statement, 1) ?? ""
            let visitTimeMicros = sqlite3_column_int64(statement, 2)
            let durationMicros = sqlite3_column_int64(statement, 3)

            let unixTimestamp = (Double(visitTimeMicros) / Self.chromiumMicrosPerSecond) - Self.chromiumEpochOffset
            let date = Date(timeIntervalSince1970: unixTimestamp)
            let duration = durationMicros > 0 ? Double(durationMicros) / Self.chromiumMicrosPerSecond : nil
            let domain = Self.extractDomain(from: url)

            visits.append(BrowsingVisit(
                id: "chrome-\(visitTimeMicros)-\(url.hashValue)",
                url: url,
                title: title.isEmpty ? domain : title,
                domain: domain,
                visitTime: date,
                durationSeconds: duration,
                browser: .chrome
            ))
        }
        return visits
    }

    // MARK: - Safari top domains

    private func fetchTopDomainsFromSafari(
        startDate: Date, endDate: Date, limit: Int
    ) throws -> [DomainSummary] {
        let (db, tempURL) = try openDatabase(for: .safari)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startApple = startDate.timeIntervalSince1970 - Self.appleEpochOffset
        let endApple = endDate.timeIntervalSince1970 - Self.appleEpochOffset

        let sql = """
        SELECT
            COALESCE(NULLIF(hi.domain_expansion, ''), hi.url) AS domain,
            COUNT(*) AS visit_count,
            MAX(hv.visit_time) AS last_visit
        FROM history_visits hv
        JOIN history_items hi ON hi.id = hv.history_item
        WHERE hv.visit_time >= ?1 AND hv.visit_time <= ?2
          AND hv.load_successful = 1
        GROUP BY domain
        ORDER BY visit_count DESC
        LIMIT ?3
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startApple)
        sqlite3_bind_double(statement, 2, endApple)
        sqlite3_bind_int(statement, 3, Int32(limit))

        var results: [DomainSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rawDomain = Self.columnText(statement, 0) ?? ""
            let count = Int(sqlite3_column_int64(statement, 1))
            let lastVisit = sqlite3_column_double(statement, 2)

            let domain = rawDomain.hasPrefix("http") ? Self.extractDomain(from: rawDomain) : rawDomain
            let lastDate = Date(timeIntervalSince1970: lastVisit + Self.appleEpochOffset)

            results.append(DomainSummary(
                domain: domain,
                visitCount: count,
                totalDurationSeconds: nil,
                lastVisitTime: lastDate
            ))
        }
        return results
    }

    // MARK: - Chrome top domains

    private func fetchTopDomainsFromChrome(
        startDate: Date, endDate: Date, limit: Int
    ) throws -> [DomainSummary] {
        let (db, tempURL) = try openDatabase(for: .chrome)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startChrome = (startDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond
        let endChrome = (endDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond

        // Chrome doesn't store domain separately — we extract it in Swift
        let sql = """
        SELECT u.url, v.visit_time, v.visit_duration
        FROM visits v
        JOIN urls u ON u.id = v.url
        WHERE v.visit_time >= ?1 AND v.visit_time <= ?2
        ORDER BY v.visit_time DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startChrome)
        sqlite3_bind_double(statement, 2, endChrome)

        // Aggregate in Swift
        var domainMap: [String: (count: Int, duration: Double, lastVisit: Date)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = Self.columnText(statement, 0) ?? ""
            let visitTimeMicros = sqlite3_column_int64(statement, 1)
            let durationMicros = sqlite3_column_int64(statement, 2)

            let domain = Self.extractDomain(from: url)
            guard !domain.isEmpty else { continue }

            let unixTime = (Double(visitTimeMicros) / Self.chromiumMicrosPerSecond) - Self.chromiumEpochOffset
            let date = Date(timeIntervalSince1970: unixTime)
            let dur = Double(durationMicros) / Self.chromiumMicrosPerSecond

            if var existing = domainMap[domain] {
                existing.count += 1
                existing.duration += dur
                if date > existing.lastVisit { existing.lastVisit = date }
                domainMap[domain] = existing
            } else {
                domainMap[domain] = (1, dur, date)
            }
        }

        return domainMap.map { domain, values in
            DomainSummary(
                domain: domain,
                visitCount: values.count,
                totalDurationSeconds: values.duration > 0 ? values.duration : nil,
                lastVisitTime: values.lastVisit
            )
        }
        .sorted { $0.visitCount > $1.visitCount }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: - Safari daily counts

    private func fetchDailyCountsFromSafari(startDate: Date, endDate: Date) throws -> [DailyVisitCount] {
        let (db, tempURL) = try openDatabase(for: .safari)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startApple = startDate.timeIntervalSince1970 - Self.appleEpochOffset
        let endApple = endDate.timeIntervalSince1970 - Self.appleEpochOffset

        // Convert Apple epoch to local date string inside SQL
        let sql = """
        SELECT DATE(hv.visit_time + \(Self.appleEpochOffset), 'unixepoch', 'localtime') AS day,
               COUNT(*) AS cnt
        FROM history_visits hv
        WHERE hv.visit_time >= ?1 AND hv.visit_time <= ?2
          AND hv.load_successful = 1
        GROUP BY day
        ORDER BY day
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startApple)
        sqlite3_bind_double(statement, 2, endApple)

        let formatter = Self.dayFormatter()
        var results: [DailyVisitCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let dayStr = Self.columnText(statement, 0) ?? ""
            let count = Int(sqlite3_column_int64(statement, 1))
            if let date = formatter.date(from: dayStr) {
                results.append(DailyVisitCount(date: date, visitCount: count))
            }
        }
        return results
    }

    // MARK: - Chrome daily counts

    private func fetchDailyCountsFromChrome(startDate: Date, endDate: Date) throws -> [DailyVisitCount] {
        let (db, tempURL) = try openDatabase(for: .chrome)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startChrome = (startDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond
        let endChrome = (endDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond

        // Chromium timestamp → Unix → local date
        let sql = """
        SELECT DATE(v.visit_time / 1000000 - \(Int64(Self.chromiumEpochOffset)), 'unixepoch', 'localtime') AS day,
               COUNT(*) AS cnt
        FROM visits v
        WHERE v.visit_time >= ?1 AND v.visit_time <= ?2
        GROUP BY day
        ORDER BY day
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startChrome)
        sqlite3_bind_double(statement, 2, endChrome)

        let formatter = Self.dayFormatter()
        var results: [DailyVisitCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let dayStr = Self.columnText(statement, 0) ?? ""
            let count = Int(sqlite3_column_int64(statement, 1))
            if let date = formatter.date(from: dayStr) {
                results.append(DailyVisitCount(date: date, visitCount: count))
            }
        }
        return results
    }

    // MARK: - Safari hourly counts

    private func fetchHourlyCountsFromSafari(startDate: Date, endDate: Date) throws -> [HourlyVisitCount] {
        let (db, tempURL) = try openDatabase(for: .safari)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startApple = startDate.timeIntervalSince1970 - Self.appleEpochOffset
        let endApple = endDate.timeIntervalSince1970 - Self.appleEpochOffset

        let sql = """
        SELECT CAST(STRFTIME('%H', hv.visit_time + \(Self.appleEpochOffset), 'unixepoch', 'localtime') AS INTEGER) AS hr,
               COUNT(*) AS cnt
        FROM history_visits hv
        WHERE hv.visit_time >= ?1 AND hv.visit_time <= ?2
          AND hv.load_successful = 1
        GROUP BY hr
        ORDER BY hr
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startApple)
        sqlite3_bind_double(statement, 2, endApple)

        var results: [HourlyVisitCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let hour = Int(sqlite3_column_int64(statement, 0))
            let count = Int(sqlite3_column_int64(statement, 1))
            results.append(HourlyVisitCount(hour: hour, visitCount: count))
        }
        return results
    }

    // MARK: - Chrome hourly counts

    private func fetchHourlyCountsFromChrome(startDate: Date, endDate: Date) throws -> [HourlyVisitCount] {
        let (db, tempURL) = try openDatabase(for: .chrome)
        defer { closeDatabase(db, tempURL: tempURL) }

        let startChrome = (startDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond
        let endChrome = (endDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond

        let sql = """
        SELECT CAST(STRFTIME('%H', v.visit_time / 1000000 - \(Int64(Self.chromiumEpochOffset)), 'unixepoch', 'localtime') AS INTEGER) AS hr,
               COUNT(*) AS cnt
        FROM visits v
        WHERE v.visit_time >= ?1 AND v.visit_time <= ?2
        GROUP BY hr
        ORDER BY hr
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: tempURL.path, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startChrome)
        sqlite3_bind_double(statement, 2, endChrome)

        var results: [HourlyVisitCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let hour = Int(sqlite3_column_int64(statement, 0))
            let count = Int(sqlite3_column_int64(statement, 1))
            results.append(HourlyVisitCount(hour: hour, visitCount: count))
        }
        return results
    }

    // MARK: - Dispatcher methods

    private func fetchVisitsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date,
        searchText: String, limit: Int
    ) async throws -> [BrowsingVisit] {
        switch browser {
        case .safari:
            return try fetchVisitsFromSafari(startDate: startDate, endDate: endDate, searchText: searchText, limit: limit)
        case .chrome:
            return try fetchVisitsFromChrome(startDate: startDate, endDate: endDate, searchText: searchText, limit: limit)
        case .all:
            return []
        }
    }

    private func fetchTopDomainsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date, limit: Int
    ) async throws -> [DomainSummary] {
        switch browser {
        case .safari:
            return try fetchTopDomainsFromSafari(startDate: startDate, endDate: endDate, limit: limit)
        case .chrome:
            return try fetchTopDomainsFromChrome(startDate: startDate, endDate: endDate, limit: limit)
        case .all:
            return []
        }
    }

    private func fetchDailyCountsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date
    ) async throws -> [DailyVisitCount] {
        switch browser {
        case .safari:
            return try fetchDailyCountsFromSafari(startDate: startDate, endDate: endDate)
        case .chrome:
            return try fetchDailyCountsFromChrome(startDate: startDate, endDate: endDate)
        case .all:
            return []
        }
    }

    private func fetchHourlyCountsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date
    ) async throws -> [HourlyVisitCount] {
        switch browser {
        case .safari:
            return try fetchHourlyCountsFromSafari(startDate: startDate, endDate: endDate)
        case .chrome:
            return try fetchHourlyCountsFromChrome(startDate: startDate, endDate: endDate)
        case .all:
            return []
        }
    }

    // MARK: - SQLite helpers

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cStr)
    }
}
