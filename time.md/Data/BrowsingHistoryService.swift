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

// MARK: - Archive sync coordination

private actor WebHistoryArchiveSyncCoordinator {
    static let shared = WebHistoryArchiveSyncCoordinator()

    private var tasks: [String: Task<Void, Error>] = [:]
    private var lastSuccessfulSync: [String: Date] = [:]
    private let minimumSyncInterval: TimeInterval = 60

    func run(key: String, operation: @escaping @Sendable () async throws -> Void) async throws {
        let now = Date()
        if let last = lastSuccessfulSync[key], now.timeIntervalSince(last) < minimumSyncInterval {
            return
        }

        if let existing = tasks[key] {
            try await existing.value
            return
        }

        let task = Task {
            try await operation()
        }
        tasks[key] = task

        do {
            try await task.value
            lastSuccessfulSync[key] = Date()
            tasks[key] = nil
        } catch {
            tasks[key] = nil
            throw error
        }
    }
}

// MARK: - Implementation

final class SQLiteBrowsingHistoryService: BrowsingHistoryServing, @unchecked Sendable {
    // Time epoch offsets
    private static let appleEpochOffset: Double = 978_307_200          // seconds: 2001-01-01 → Unix
    private static let chromiumEpochOffset: Double = 11_644_473_600    // seconds: 1601-01-01 → Unix
    private static let chromiumMicrosPerSecond: Double = 1_000_000
    private static let firefoxMicrosPerSecond: Double = 1_000_000

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Database cache (avoids repeated copying)

    private struct CachedDatabase {
        let db: OpaquePointer
        let tempURL: URL
        let createdAt: Date
    }

    private static let cacheLock = NSLock()
    private static var databaseCache: [String: CachedDatabase] = [:]
    private static let cacheValidityDuration: TimeInterval = 60  // 60 seconds
    private static let archiveSyncVisitLimit = 200_000

    /// Clean up expired cached databases
    private static func cleanupExpiredCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let now = Date()
        var expiredKeys: [String] = []
        for (cacheKey, cached) in databaseCache {
            if now.timeIntervalSince(cached.createdAt) > cacheValidityDuration {
                sqlite3_close(cached.db)
                try? FileManager.default.removeItem(at: cached.tempURL.deletingLastPathComponent())
                expiredKeys.append(cacheKey)
            }
        }
        for cacheKey in expiredKeys {
            databaseCache.removeValue(forKey: cacheKey)
        }
    }

    /// Invalidate all cached databases (call when app goes to background or on memory warning)
    static func invalidateCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        for (_, cached) in databaseCache {
            sqlite3_close(cached.db)
            try? FileManager.default.removeItem(at: cached.tempURL.deletingLastPathComponent())
        }
        databaseCache.removeAll()
    }

    /// Prefetch databases in the background to warm up the cache.
    /// Call this early (e.g., at app launch) to ensure instant loading when user opens Web History.
    func prefetchDatabases() {
        Task.detached(priority: .utility) {
            let service = SQLiteBrowsingHistoryService()
            let browsers = service.availableBrowsers().filter { $0 != .all }

            for browser in browsers {
                do {
                    _ = try service.getCachedDatabases(for: browser)
                } catch {
                    // Silently ignore errors during prefetch
                }
            }

            if WebHistoryArchiveStore.isEnabled {
                await service.snapshotRecentHistoryForPersistence(days: 90)
            }
        }
    }

    /// Snapshots recent browser visits into time.md's local archive when the
    /// explicit persistence setting is enabled.
    func snapshotRecentHistoryForPersistence(days: Int = 90) async {
        guard WebHistoryArchiveStore.isEnabled else { return }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)
            ?? endDate.addingTimeInterval(-Double(days) * 24 * 60 * 60)

        do {
            try await syncArchiveIfNeeded(browser: .all, startDate: startDate, endDate: endDate)
        } catch {
            NSLog("[WebHistoryArchive] recent snapshot failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Database paths

    private static var safariHistoryURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Safari/History.db")
    }

    private static var chromeHistoryURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/History")
    }

    private static var firefoxProfilesDirectory: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
    }

    private static func firefoxHistoryURLs() -> [URL] {
        let profilesDirectory = firefoxProfilesDirectory
        guard let profileDirectories = try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return profileDirectories.compactMap { profileDirectory -> URL? in
            let values = try? profileDirectory.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }

            let places = profileDirectory.appendingPathComponent("places.sqlite")
            return FileManager.default.fileExists(atPath: places.path) ? places : nil
        }
        .sorted { lhs, rhs in
            let lhsProfile = lhs.deletingLastPathComponent()
            let rhsProfile = rhs.deletingLastPathComponent()
            let lhsName = lhsProfile.lastPathComponent.lowercased()
            let rhsName = rhsProfile.lastPathComponent.lowercased()
            let lhsScore = firefoxProfileSortScore(lhsName)
            let rhsScore = firefoxProfileSortScore(rhsName)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            let lhsModified = (try? lhsProfile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsModified = (try? rhsProfile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if lhsModified != rhsModified {
                return lhsModified > rhsModified
            }

            return lhsName < rhsName
        }
    }

    private static func firefoxProfileSortScore(_ profileName: String) -> Int {
        if profileName.contains("default-release") { return 0 }
        if profileName.contains("default") { return 1 }
        if profileName.contains("release") { return 2 }
        return 3
    }

    private static var arcHistoryURL: URL {
        // Arc stores history in the Default profile or Profile 1
        let appSupport = realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Arc/User Data")

        // Check Default profile first, then numbered profiles
        let defaultPath = appSupport.appendingPathComponent("Default/History")
        if FileManager.default.fileExists(atPath: defaultPath.path) {
            return defaultPath
        }
        // Fall back to Profile 1 if Default doesn't exist
        return appSupport.appendingPathComponent("Profile 1/History")
    }

    private static var braveHistoryURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/Default/History")
    }

    private static var edgeHistoryURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Microsoft Edge/Default/History")
    }

    // MARK: - Available browsers

    func availableBrowsers() -> [BrowserSource] {
        var sources = installedBrowsers()
        if WebHistoryArchiveStore.isEnabled,
           let archived = try? WebHistoryArchiveStore.archivedBrowsersSync() {
            for browser in archived where browser != .all && !sources.contains(browser) {
                sources.append(browser)
            }
        }
        if sources.count > 1 {
            sources.insert(.all, at: 0)
        }
        return sources
    }

    private func installedBrowsers() -> [BrowserSource] {
        var sources: [BrowserSource] = []
        if FileManager.default.fileExists(atPath: Self.safariHistoryURL.path) {
            sources.append(.safari)
        }
        if FileManager.default.fileExists(atPath: Self.chromeHistoryURL.path) {
            sources.append(.chrome)
        }
        if !Self.firefoxHistoryURLs().isEmpty {
            sources.append(.firefox)
        }
        if FileManager.default.fileExists(atPath: Self.arcHistoryURL.path) {
            sources.append(.arc)
        }
        if FileManager.default.fileExists(atPath: Self.braveHistoryURL.path) {
            sources.append(.brave)
        }
        if FileManager.default.fileExists(atPath: Self.edgeHistoryURL.path) {
            sources.append(.edge)
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
        if WebHistoryArchiveStore.isEnabled {
            let syncError = await archiveSyncError(browser: browser, startDate: startDate, endDate: endDate)
            let archived = try await fetchArchivedVisits(
                browser: browser,
                startDate: startDate,
                endDate: endDate,
                searchText: searchText,
                limit: limit
            )
            if archived.isEmpty, let syncError {
                throw syncError
            }
            return archived
        }

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
        if WebHistoryArchiveStore.isEnabled {
            let syncError = await archiveSyncError(browser: browser, startDate: startDate, endDate: endDate)
            let archived = try await fetchArchivedTopDomains(
                browser: browser,
                startDate: startDate,
                endDate: endDate,
                limit: limit
            )
            if archived.isEmpty, let syncError {
                throw syncError
            }
            return archived
        }

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
        if WebHistoryArchiveStore.isEnabled {
            let syncError = await archiveSyncError(browser: browser, startDate: startDate, endDate: endDate)
            let archived = try await fetchArchivedDailyVisitCounts(
                browser: browser,
                startDate: startDate,
                endDate: endDate
            )
            if archived.isEmpty, let syncError {
                throw syncError
            }
            return archived
        }

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
        if WebHistoryArchiveStore.isEnabled {
            let syncError = await archiveSyncError(browser: browser, startDate: startDate, endDate: endDate)
            let archived = try await fetchArchivedHourlyVisitCounts(
                browser: browser,
                startDate: startDate,
                endDate: endDate
            )
            let hasVisits = archived.contains { $0.visitCount > 0 }
            if !hasVisits, let syncError {
                throw syncError
            }
            return archived
        }

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

    // MARK: - Fetch pages for domain

    func fetchPagesForDomain(
        domain: String,
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [PageSummary] {
        if WebHistoryArchiveStore.isEnabled {
            let syncError = await archiveSyncError(browser: browser, startDate: startDate, endDate: endDate)
            let archived = try await fetchArchivedPagesForDomain(
                domain: domain,
                browser: browser,
                startDate: startDate,
                endDate: endDate,
                limit: limit
            )
            if archived.isEmpty, let syncError {
                throw syncError
            }
            return archived
        }

        var allPageVisits: [PageVisit] = []
        let browsers = resolveBrowsers(browser)

        for b in browsers {
            let visits = try await fetchPageVisitsFromBrowser(
                b, domain: domain, startDate: startDate, endDate: endDate
            )
            allPageVisits.append(contentsOf: visits)
        }

        // Group by path
        var pathGroups: [String: [PageVisit]] = [:]
        for visit in allPageVisits {
            pathGroups[visit.path, default: []].append(visit)
        }

        // Build summaries
        var summaries: [PageSummary] = []
        for (path, visits) in pathGroups {
            let sortedVisits = visits.sorted { $0.visitTime > $1.visitTime }
            let latestTitle = sortedVisits.first?.title ?? path
            let lastVisit = sortedVisits.first?.visitTime ?? Date.distantPast
            let totalDuration = sortedVisits.compactMap(\.durationSeconds).reduce(0, +)

            summaries.append(PageSummary(
                path: path,
                title: latestTitle,
                visitCount: visits.count,
                visits: sortedVisits,
                lastVisitTime: lastVisit,
                totalDurationSeconds: totalDuration > 0 ? totalDuration : nil
            ))
        }

        return summaries
            .sorted { $0.visitCount > $1.visitCount }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Helpers

    private func archiveSyncError(browser: BrowserSource, startDate: Date, endDate: Date) async -> Error? {
        do {
            try await syncArchiveIfNeeded(browser: browser, startDate: startDate, endDate: endDate)
            return nil
        } catch {
            return error
        }
    }

    private func syncArchiveIfNeeded(browser: BrowserSource, startDate: Date, endDate: Date) async throws {
        let browsers = resolveBrowsers(browser)
        var firstError: Error?

        for source in browsers {
            let key = Self.archiveSyncKey(browser: source, startDate: startDate, endDate: endDate)
            do {
                try await WebHistoryArchiveSyncCoordinator.shared.run(key: key) { [self] in
                    let visits = try await self.fetchVisitsFromBrowser(
                        source,
                        startDate: startDate,
                        endDate: endDate,
                        searchText: "",
                        limit: Self.archiveSyncVisitLimit
                    )
                    try await WebHistoryArchiveStore.upsert(visits)
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private static func archiveSyncKey(browser: BrowserSource, startDate: Date, endDate: Date) -> String {
        let startHour = Int(startDate.timeIntervalSince1970 / 3600)
        let endHour = Int(endDate.timeIntervalSince1970 / 3600)
        return "\(browser.rawValue)|\(startHour)|\(endHour)"
    }

    private func archiveQueryBrowsers(_ source: BrowserSource) -> [BrowserSource] {
        switch source {
        case .all:
            return BrowserSource.allCases.filter { $0 != .all && BrowserSettingsStore.shared.isEnabled($0) }
        case .safari, .chrome, .firefox, .arc, .brave, .edge:
            return BrowserSettingsStore.shared.isEnabled(source) ? [source] : []
        }
    }

    private func fetchArchivedVisits(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) async throws -> [BrowsingVisit] {
        var allVisits: [BrowsingVisit] = []
        for source in archiveQueryBrowsers(browser) {
            let visits = try await WebHistoryArchiveStore.fetchVisits(
                browser: source,
                startDate: startDate,
                endDate: endDate,
                searchText: searchText,
                limit: limit
            )
            allVisits.append(contentsOf: visits)
        }

        allVisits.sort { $0.visitTime > $1.visitTime }
        return allVisits.count > limit ? Array(allVisits.prefix(limit)) : allVisits
    }

    private func fetchArchivedTopDomains(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [DomainSummary] {
        var merged: [String: (count: Int, duration: Double?, lastVisit: Date)] = [:]

        for source in archiveQueryBrowsers(browser) {
            let domains = try await WebHistoryArchiveStore.fetchTopDomains(
                browser: source,
                startDate: startDate,
                endDate: endDate,
                limit: 500
            )
            for domain in domains {
                if var existing = merged[domain.domain] {
                    existing.count += domain.visitCount
                    if let duration = domain.totalDurationSeconds {
                        existing.duration = (existing.duration ?? 0) + duration
                    }
                    if domain.lastVisitTime > existing.lastVisit {
                        existing.lastVisit = domain.lastVisitTime
                    }
                    merged[domain.domain] = existing
                } else {
                    merged[domain.domain] = (domain.visitCount, domain.totalDurationSeconds, domain.lastVisitTime)
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

    private func fetchArchivedDailyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailyVisitCount] {
        var merged: [String: Int] = [:]
        let formatter = Self.dayFormatter()

        for source in archiveQueryBrowsers(browser) {
            let counts = try await WebHistoryArchiveStore.fetchDailyVisitCounts(
                browser: source,
                startDate: startDate,
                endDate: endDate
            )
            for count in counts {
                let key = formatter.string(from: count.date)
                merged[key, default: 0] += count.visitCount
            }
        }

        return merged.compactMap { key, count in
            guard let date = formatter.date(from: key) else { return nil }
            return DailyVisitCount(date: date, visitCount: count)
        }
        .sorted { $0.date < $1.date }
    }

    private func fetchArchivedHourlyVisitCounts(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date
    ) async throws -> [HourlyVisitCount] {
        var merged: [Int: Int] = [:]

        for source in archiveQueryBrowsers(browser) {
            let counts = try await WebHistoryArchiveStore.fetchHourlyVisitCounts(
                browser: source,
                startDate: startDate,
                endDate: endDate
            )
            for count in counts {
                merged[count.hour, default: 0] += count.visitCount
            }
        }

        return (0..<24).map { hour in
            HourlyVisitCount(hour: hour, visitCount: merged[hour] ?? 0)
        }
    }

    private func fetchArchivedPagesForDomain(
        domain: String,
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [PageSummary] {
        var pathGroups: [String: [PageVisit]] = [:]

        for source in archiveQueryBrowsers(browser) {
            let pages = try await WebHistoryArchiveStore.fetchPagesForDomain(
                domain: domain,
                browser: source,
                startDate: startDate,
                endDate: endDate,
                limit: 500
            )
            for page in pages {
                pathGroups[page.path, default: []].append(contentsOf: page.visits)
            }
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

    private func resolveBrowsers(_ source: BrowserSource) -> [BrowserSource] {
        switch source {
        case .all:
            return installedBrowsers().filter { BrowserSettingsStore.shared.isEnabled($0) }
        case .safari, .chrome, .firefox, .arc, .brave, .edge:
            return BrowserSettingsStore.shared.isEnabled(source) ? [source] : []
        }
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    // MARK: - URL sanitization

    /// Non-web-page URL schemes we never want in browsing history exports.
    /// `data:` URIs are the main offender — browsers occasionally log them
    /// as visits and the base64 payload can be tens of kilobytes, which
    /// blows up both the url and domain columns in downstream exports.
    private static let blockedURLSchemes: Set<String> = [
        "data", "blob", "javascript", "about",
        "chrome", "chrome-extension", "edge", "brave", "arc", "moz-extension",
        "file", "filesystem", "view-source", "resource", "place",
    ]
    private static let maxURLLength = 2048

    /// Drops URLs with non-page schemes and caps the length. Returns nil if
    /// the URL should be skipped entirely.
    private static func sanitizeURL(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        for scheme in blockedURLSchemes where lower.hasPrefix("\(scheme):") {
            return nil
        }
        if raw.count > maxURLLength {
            return String(raw.prefix(maxURLLength))
        }
        return raw
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
            // Last-ditch fallback: cap length so a malformed URL that slips
            // past sanitizeURL can't bloat the domain column.
            return urlString.count > 256 ? String(urlString.prefix(256)) : urlString
        }
        // Strip www. prefix
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    // MARK: - Path extraction

    private static func extractPath(from urlString: String) -> String {
        guard let comps = URLComponents(string: urlString) else {
            return "/"
        }
        let path = comps.path.isEmpty ? "/" : comps.path
        // Normalize trailing slashes and return a clean path
        return path == "/" ? "/" : path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "/" : path
    }

    private static func matchesDomain(_ urlString: String, domain: String) -> Bool {
        let extracted = extractDomain(from: urlString)
        // Match exact or with www. prefix
        return extracted.lowercased() == domain.lowercased() ||
               extracted.lowercased() == "www.\(domain.lowercased())"
    }

    // MARK: - Open database (with caching to avoid repeated copies)

    /// Returns a cached database handle if available and valid, otherwise creates a new copy.
    /// Cached databases are reused for 60 seconds to avoid expensive re-copying on each query.
    private func getCachedDatabase(for browser: BrowserSource) throws -> OpaquePointer {
        let sourceURL = try primaryDatabaseURL(for: browser)
        return try getCachedDatabase(for: browser, sourceURL: sourceURL)
    }

    /// Returns cached handles for browser sources that can have multiple profile databases.
    private func getCachedDatabases(for browser: BrowserSource) throws -> [OpaquePointer] {
        switch browser {
        case .firefox:
            let sourceURLs = Self.firefoxHistoryURLs()
            guard !sourceURLs.isEmpty else {
                throw BrowsingHistoryError.databaseNotFound(browser: browser.rawValue)
            }
            return try sourceURLs.map { try getCachedDatabase(for: browser, sourceURL: $0) }
        default:
            return [try getCachedDatabase(for: browser)]
        }
    }

    private func getCachedDatabase(for browser: BrowserSource, sourceURL: URL) throws -> OpaquePointer {
        // Clean up expired entries periodically
        Self.cleanupExpiredCache()

        let cacheKey = Self.databaseCacheKey(for: browser, sourceURL: sourceURL)
        Self.cacheLock.lock()

        // Check if we have a valid cached copy
        if let cached = Self.databaseCache[cacheKey] {
            let age = Date().timeIntervalSince(cached.createdAt)
            if age < Self.cacheValidityDuration {
                Self.cacheLock.unlock()
                return cached.db
            } else {
                // Expired - close and remove
                sqlite3_close(cached.db)
                try? FileManager.default.removeItem(at: cached.tempURL.deletingLastPathComponent())
                Self.databaseCache.removeValue(forKey: cacheKey)
            }
        }
        Self.cacheLock.unlock()

        // Create new cached copy
        let (db, tempURL) = try openDatabaseUncached(for: browser, sourceURL: sourceURL)

        Self.cacheLock.lock()
        Self.databaseCache[cacheKey] = CachedDatabase(db: db, tempURL: tempURL, createdAt: Date())
        Self.cacheLock.unlock()

        return db
    }

    private func primaryDatabaseURL(for browser: BrowserSource) throws -> URL {
        switch browser {
        case .safari:
            return Self.safariHistoryURL
        case .chrome:
            return Self.chromeHistoryURL
        case .firefox:
            guard let sourceURL = Self.firefoxHistoryURLs().first else {
                throw BrowsingHistoryError.databaseNotFound(browser: browser.rawValue)
            }
            return sourceURL
        case .arc:
            return Self.arcHistoryURL
        case .brave:
            return Self.braveHistoryURL
        case .edge:
            return Self.edgeHistoryURL
        case .all:
            fatalError("Should not request a database URL for .all")
        }
    }

    private static func databaseCacheKey(for browser: BrowserSource, sourceURL: URL) -> String {
        "\(browser.rawValue)|\(sourceURL.path)"
    }

    /// Creates a fresh database copy (internal, used by caching layer)
    private func openDatabaseUncached(for browser: BrowserSource, sourceURL: URL) throws -> (db: OpaquePointer, tempURL: URL) {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw BrowsingHistoryError.databaseNotFound(browser: browser.rawValue)
        }

        // Copy to temp to avoid locking the browser's live database
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("time.md-BH-\(browser.rawValue)-\(UUID().uuidString)", isDirectory: true)
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
            // Backup init failed - fall back to file copy
            return try openDatabaseWithFileCopy(sourceURL: sourceURL, tempDB: tempDB)
        }

        var step: Int32 = SQLITE_OK
        var retries = 0
        repeat {
            step = sqlite3_backup_step(backup, -1)
            if step == SQLITE_BUSY || step == SQLITE_LOCKED {
                retries += 1
                if retries > 200 { break }
                sqlite3_sleep(50)
            }
        } while step == SQLITE_BUSY || step == SQLITE_LOCKED

        let finish = sqlite3_backup_finish(backup)

        guard step == SQLITE_DONE, finish == SQLITE_OK else {
            sqlite3_close(dstDB)
            // Backup failed due to locking - fall back to file copy
            return try openDatabaseWithFileCopy(sourceURL: sourceURL, tempDB: tempDB)
        }

        return (dstDB, tempDB)
    }

    /// Fallback method when sqlite3_backup fails due to database locking
    /// Copies the file directly and opens in immutable mode
    private func openDatabaseWithFileCopy(sourceURL: URL, tempDB: URL) throws -> (db: OpaquePointer, tempURL: URL) {
        // Remove any existing temp file
        try? FileManager.default.removeItem(at: tempDB)

        // Direct file copy - may get an inconsistent snapshot but usually works
        try FileManager.default.copyItem(at: sourceURL, to: tempDB)

        // Also copy WAL and SHM files if they exist (for WAL mode databases)
        let walURL = sourceURL.appendingPathExtension("wal")
        let shmURL = sourceURL.appendingPathExtension("shm")
        let tempWAL = tempDB.appendingPathExtension("wal")
        let tempSHM = tempDB.appendingPathExtension("shm")

        if FileManager.default.fileExists(atPath: walURL.path) {
            try? FileManager.default.copyItem(at: walURL, to: tempWAL)
        }
        if FileManager.default.fileExists(atPath: shmURL.path) {
            try? FileManager.default.copyItem(at: shmURL, to: tempSHM)
        }

        // Open in read-only mode
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            tempDB.path, &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw BrowsingHistoryError.sqlite(path: tempDB.path, message: "Failed to open copied database (code \(result))")
        }

        // Run integrity check and checkpoint to consolidate WAL
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)

        return (db, tempDB)
    }

    // MARK: - Safari queries

    private func fetchVisitsFromSafari(
        startDate: Date, endDate: Date, searchText: String, limit: Int
    ) throws -> [BrowsingVisit] {
        let db = try getCachedDatabase(for: .safari)

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
            throw BrowsingHistoryError.sqlite(path: "Safari", message: msg)
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
            guard let url = Self.sanitizeURL(Self.columnText(statement, 0) ?? "") else { continue }
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

    // MARK: - Chromium queries (Chrome, Arc, Brave, Edge)

    private func fetchVisitsFromChromium(
        browser: BrowserSource, startDate: Date, endDate: Date, searchText: String, limit: Int
    ) throws -> [BrowsingVisit] {
        let db = try getCachedDatabase(for: browser)

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
            throw BrowsingHistoryError.sqlite(path: browser.rawValue, message: msg)
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
            guard let url = Self.sanitizeURL(Self.columnText(statement, 0) ?? "") else { continue }
            let title = Self.columnText(statement, 1) ?? ""
            let visitTimeMicros = sqlite3_column_int64(statement, 2)
            let durationMicros = sqlite3_column_int64(statement, 3)

            let unixTimestamp = (Double(visitTimeMicros) / Self.chromiumMicrosPerSecond) - Self.chromiumEpochOffset
            let date = Date(timeIntervalSince1970: unixTimestamp)
            let duration = durationMicros > 0 ? Double(durationMicros) / Self.chromiumMicrosPerSecond : nil
            let domain = Self.extractDomain(from: url)

            visits.append(BrowsingVisit(
                id: "\(browser.rawValue.lowercased())-\(visitTimeMicros)-\(url.hashValue)",
                url: url,
                title: title.isEmpty ? domain : title,
                domain: domain,
                visitTime: date,
                durationSeconds: duration,
                browser: browser
            ))
        }
        return visits
    }

    // MARK: - Firefox queries

    private func fetchVisitsFromFirefox(
        startDate: Date, endDate: Date, searchText: String, limit: Int
    ) throws -> [BrowsingVisit] {
        var allVisits: [BrowsingVisit] = []
        for db in try getCachedDatabases(for: .firefox) {
            allVisits.append(contentsOf: try fetchVisitsFromFirefoxDatabase(
                db,
                startDate: startDate,
                endDate: endDate,
                searchText: searchText,
                limit: limit
            ))
        }

        allVisits.sort { $0.visitTime > $1.visitTime }
        return allVisits.count > limit ? Array(allVisits.prefix(limit)) : allVisits
    }

    private func fetchVisitsFromFirefoxDatabase(
        _ db: OpaquePointer,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) throws -> [BrowsingVisit] {
        let startFirefox = Int64(startDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)
        let endFirefox = Int64(endDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)

        var sql = """
        SELECT p.url, p.title, v.visit_date
        FROM moz_historyvisits v
        JOIN moz_places p ON p.id = v.place_id
        WHERE v.visit_date >= ?1 AND v.visit_date <= ?2
          AND IFNULL(p.hidden, 0) = 0
        """
        if !searchText.isEmpty {
            sql += " AND (p.url LIKE ?3 OR p.title LIKE ?3 OR p.rev_host LIKE ?3)"
        }
        sql += " ORDER BY v.visit_date DESC LIMIT ?4"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: "Firefox", message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, startFirefox)
        sqlite3_bind_int64(statement, 2, endFirefox)
        if !searchText.isEmpty {
            let pattern = "%\(searchText)%"
            sqlite3_bind_text(statement, 3, pattern, -1, Self.sqliteTransient)
            sqlite3_bind_int64(statement, 4, Int64(limit))
        } else {
            sqlite3_bind_int64(statement, 4, Int64(limit))
        }

        var visits: [BrowsingVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let url = Self.sanitizeURL(Self.columnText(statement, 0) ?? "") else { continue }
            let title = Self.columnText(statement, 1) ?? ""
            let visitTimeMicros = sqlite3_column_int64(statement, 2)

            let unixTimestamp = Double(visitTimeMicros) / Self.firefoxMicrosPerSecond
            let date = Date(timeIntervalSince1970: unixTimestamp)
            let domain = Self.extractDomain(from: url)

            visits.append(BrowsingVisit(
                id: "firefox-\(visitTimeMicros)-\(url.hashValue)",
                url: url,
                title: title.isEmpty ? domain : title,
                domain: domain,
                visitTime: date,
                durationSeconds: nil,
                browser: .firefox
            ))
        }
        return visits
    }

    // MARK: - Safari top domains

    private func fetchTopDomainsFromSafari(
        startDate: Date, endDate: Date, limit: Int
    ) throws -> [DomainSummary] {
        let db = try getCachedDatabase(for: .safari)

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
            throw BrowsingHistoryError.sqlite(path: "Safari", message: msg)
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

    // MARK: - Chromium top domains

    private func fetchTopDomainsFromChromium(
        browser: BrowserSource, startDate: Date, endDate: Date, limit: Int
    ) throws -> [DomainSummary] {
        let db = try getCachedDatabase(for: browser)

        let startChrome = (startDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond
        let endChrome = (endDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond

        // Chromium doesn't store domain separately — we extract it in Swift
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
            throw BrowsingHistoryError.sqlite(path: browser.rawValue, message: msg)
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

    // MARK: - Firefox top domains

    private func fetchTopDomainsFromFirefox(
        startDate: Date, endDate: Date, limit: Int
    ) throws -> [DomainSummary] {
        var domainMap: [String: (count: Int, lastVisit: Date)] = [:]

        for db in try getCachedDatabases(for: .firefox) {
            let partial = try fetchTopDomainsFromFirefoxDatabase(db, startDate: startDate, endDate: endDate)
            for domain in partial {
                if var existing = domainMap[domain.domain] {
                    existing.count += domain.visitCount
                    if domain.lastVisitTime > existing.lastVisit {
                        existing.lastVisit = domain.lastVisitTime
                    }
                    domainMap[domain.domain] = existing
                } else {
                    domainMap[domain.domain] = (domain.visitCount, domain.lastVisitTime)
                }
            }
        }

        return domainMap.map { domain, values in
            DomainSummary(
                domain: domain,
                visitCount: values.count,
                totalDurationSeconds: nil,
                lastVisitTime: values.lastVisit
            )
        }
        .sorted { $0.visitCount > $1.visitCount }
        .prefix(limit)
        .map { $0 }
    }

    private func fetchTopDomainsFromFirefoxDatabase(
        _ db: OpaquePointer,
        startDate: Date,
        endDate: Date
    ) throws -> [DomainSummary] {
        let startFirefox = Int64(startDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)
        let endFirefox = Int64(endDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)

        let sql = """
        SELECT p.url, v.visit_date
        FROM moz_historyvisits v
        JOIN moz_places p ON p.id = v.place_id
        WHERE v.visit_date >= ?1 AND v.visit_date <= ?2
          AND IFNULL(p.hidden, 0) = 0
        ORDER BY v.visit_date DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: "Firefox", message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, startFirefox)
        sqlite3_bind_int64(statement, 2, endFirefox)

        var domainMap: [String: (count: Int, lastVisit: Date)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let url = Self.sanitizeURL(Self.columnText(statement, 0) ?? "") else { continue }
            let visitTimeMicros = sqlite3_column_int64(statement, 1)
            let domain = Self.extractDomain(from: url)
            guard !domain.isEmpty else { continue }

            let date = Date(timeIntervalSince1970: Double(visitTimeMicros) / Self.firefoxMicrosPerSecond)
            if var existing = domainMap[domain] {
                existing.count += 1
                if date > existing.lastVisit { existing.lastVisit = date }
                domainMap[domain] = existing
            } else {
                domainMap[domain] = (1, date)
            }
        }

        return domainMap.map { domain, values in
            DomainSummary(
                domain: domain,
                visitCount: values.count,
                totalDurationSeconds: nil,
                lastVisitTime: values.lastVisit
            )
        }
    }

    // MARK: - Safari daily counts

    private func fetchDailyCountsFromSafari(startDate: Date, endDate: Date) throws -> [DailyVisitCount] {
        let db = try getCachedDatabase(for: .safari)

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
            throw BrowsingHistoryError.sqlite(path: "Safari", message: msg)
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

    // MARK: - Chromium daily counts

    private func fetchDailyCountsFromChromium(browser: BrowserSource, startDate: Date, endDate: Date) throws -> [DailyVisitCount] {
        let db = try getCachedDatabase(for: browser)

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
            throw BrowsingHistoryError.sqlite(path: browser.rawValue, message: msg)
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

    // MARK: - Firefox daily counts

    private func fetchDailyCountsFromFirefox(startDate: Date, endDate: Date) throws -> [DailyVisitCount] {
        var merged: [String: Int] = [:]
        let formatter = Self.dayFormatter()

        for db in try getCachedDatabases(for: .firefox) {
            let counts = try fetchDailyCountsFromFirefoxDatabase(db, startDate: startDate, endDate: endDate)
            for count in counts {
                let key = formatter.string(from: count.date)
                merged[key, default: 0] += count.visitCount
            }
        }

        return merged.compactMap { key, count in
            guard let date = formatter.date(from: key) else { return nil }
            return DailyVisitCount(date: date, visitCount: count)
        }
        .sorted { $0.date < $1.date }
    }

    private func fetchDailyCountsFromFirefoxDatabase(
        _ db: OpaquePointer,
        startDate: Date,
        endDate: Date
    ) throws -> [DailyVisitCount] {
        let startFirefox = Int64(startDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)
        let endFirefox = Int64(endDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)

        let sql = """
        SELECT DATE(v.visit_date / 1000000, 'unixepoch', 'localtime') AS day,
               COUNT(*) AS cnt
        FROM moz_historyvisits v
        JOIN moz_places p ON p.id = v.place_id
        WHERE v.visit_date >= ?1 AND v.visit_date <= ?2
          AND IFNULL(p.hidden, 0) = 0
        GROUP BY day
        ORDER BY day
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: "Firefox", message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, startFirefox)
        sqlite3_bind_int64(statement, 2, endFirefox)

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
        let db = try getCachedDatabase(for: .safari)

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
            throw BrowsingHistoryError.sqlite(path: "Safari", message: msg)
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

    // MARK: - Chromium hourly counts

    private func fetchHourlyCountsFromChromium(browser: BrowserSource, startDate: Date, endDate: Date) throws -> [HourlyVisitCount] {
        let db = try getCachedDatabase(for: browser)

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
            throw BrowsingHistoryError.sqlite(path: browser.rawValue, message: msg)
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

    // MARK: - Firefox hourly counts

    private func fetchHourlyCountsFromFirefox(startDate: Date, endDate: Date) throws -> [HourlyVisitCount] {
        var merged: [Int: Int] = [:]

        for db in try getCachedDatabases(for: .firefox) {
            let counts = try fetchHourlyCountsFromFirefoxDatabase(db, startDate: startDate, endDate: endDate)
            for count in counts {
                merged[count.hour, default: 0] += count.visitCount
            }
        }

        return merged.map { hour, count in
            HourlyVisitCount(hour: hour, visitCount: count)
        }
        .sorted { $0.hour < $1.hour }
    }

    private func fetchHourlyCountsFromFirefoxDatabase(
        _ db: OpaquePointer,
        startDate: Date,
        endDate: Date
    ) throws -> [HourlyVisitCount] {
        let startFirefox = Int64(startDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)
        let endFirefox = Int64(endDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)

        let sql = """
        SELECT CAST(STRFTIME('%H', v.visit_date / 1000000, 'unixepoch', 'localtime') AS INTEGER) AS hr,
               COUNT(*) AS cnt
        FROM moz_historyvisits v
        JOIN moz_places p ON p.id = v.place_id
        WHERE v.visit_date >= ?1 AND v.visit_date <= ?2
          AND IFNULL(p.hidden, 0) = 0
        GROUP BY hr
        ORDER BY hr
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: "Firefox", message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, startFirefox)
        sqlite3_bind_int64(statement, 2, endFirefox)

        var results: [HourlyVisitCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let hour = Int(sqlite3_column_int64(statement, 0))
            let count = Int(sqlite3_column_int64(statement, 1))
            results.append(HourlyVisitCount(hour: hour, visitCount: count))
        }
        return results
    }

    // MARK: - Dispatcher methods (run on background thread to avoid blocking UI)

    private func fetchVisitsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date,
        searchText: String, limit: Int
    ) async throws -> [BrowsingVisit] {
        try await Task.detached(priority: .userInitiated) { [self] in
            switch browser {
            case .safari:
                return try fetchVisitsFromSafari(startDate: startDate, endDate: endDate, searchText: searchText, limit: limit)
            case .firefox:
                return try fetchVisitsFromFirefox(startDate: startDate, endDate: endDate, searchText: searchText, limit: limit)
            case .chrome, .arc, .brave, .edge:
                return try fetchVisitsFromChromium(browser: browser, startDate: startDate, endDate: endDate, searchText: searchText, limit: limit)
            case .all:
                return []
            }
        }.value
    }

    private func fetchTopDomainsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date, limit: Int
    ) async throws -> [DomainSummary] {
        try await Task.detached(priority: .userInitiated) { [self] in
            switch browser {
            case .safari:
                return try fetchTopDomainsFromSafari(startDate: startDate, endDate: endDate, limit: limit)
            case .firefox:
                return try fetchTopDomainsFromFirefox(startDate: startDate, endDate: endDate, limit: limit)
            case .chrome, .arc, .brave, .edge:
                return try fetchTopDomainsFromChromium(browser: browser, startDate: startDate, endDate: endDate, limit: limit)
            case .all:
                return []
            }
        }.value
    }

    private func fetchDailyCountsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date
    ) async throws -> [DailyVisitCount] {
        try await Task.detached(priority: .userInitiated) { [self] in
            switch browser {
            case .safari:
                return try fetchDailyCountsFromSafari(startDate: startDate, endDate: endDate)
            case .firefox:
                return try fetchDailyCountsFromFirefox(startDate: startDate, endDate: endDate)
            case .chrome, .arc, .brave, .edge:
                return try fetchDailyCountsFromChromium(browser: browser, startDate: startDate, endDate: endDate)
            case .all:
                return []
            }
        }.value
    }

    private func fetchHourlyCountsFromBrowser(
        _ browser: BrowserSource, startDate: Date, endDate: Date
    ) async throws -> [HourlyVisitCount] {
        try await Task.detached(priority: .userInitiated) { [self] in
            switch browser {
            case .safari:
                return try fetchHourlyCountsFromSafari(startDate: startDate, endDate: endDate)
            case .firefox:
                return try fetchHourlyCountsFromFirefox(startDate: startDate, endDate: endDate)
            case .chrome, .arc, .brave, .edge:
                return try fetchHourlyCountsFromChromium(browser: browser, startDate: startDate, endDate: endDate)
            case .all:
                return []
            }
        }.value
    }

    private func fetchPageVisitsFromBrowser(
        _ browser: BrowserSource, domain: String, startDate: Date, endDate: Date
    ) async throws -> [PageVisit] {
        try await Task.detached(priority: .userInitiated) { [self] in
            switch browser {
            case .safari:
                return try fetchPageVisitsFromSafari(domain: domain, startDate: startDate, endDate: endDate)
            case .firefox:
                return try fetchPageVisitsFromFirefox(domain: domain, startDate: startDate, endDate: endDate)
            case .chrome, .arc, .brave, .edge:
                return try fetchPageVisitsFromChromium(browser: browser, domain: domain, startDate: startDate, endDate: endDate)
            case .all:
                return []
            }
        }.value
    }

    // MARK: - Safari page visits for domain

    private func fetchPageVisitsFromSafari(
        domain: String, startDate: Date, endDate: Date
    ) throws -> [PageVisit] {
        let db = try getCachedDatabase(for: .safari)

        let startApple = startDate.timeIntervalSince1970 - Self.appleEpochOffset
        let endApple = endDate.timeIntervalSince1970 - Self.appleEpochOffset

        // Safari stores domain_expansion which we can use to filter
        let sql = """
        SELECT hi.url, hv.title, hv.visit_time
        FROM history_visits hv
        JOIN history_items hi ON hi.id = hv.history_item
        WHERE hv.visit_time >= ?1 AND hv.visit_time <= ?2
          AND hv.load_successful = 1
        ORDER BY hv.visit_time DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: "Safari", message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startApple)
        sqlite3_bind_double(statement, 2, endApple)

        var visits: [PageVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = Self.columnText(statement, 0) ?? ""
            let title = Self.columnText(statement, 1) ?? ""
            let visitTime = sqlite3_column_double(statement, 2)

            // Filter by domain in Swift
            guard Self.matchesDomain(url, domain: domain) else { continue }

            let date = Date(timeIntervalSince1970: visitTime + Self.appleEpochOffset)
            let path = Self.extractPath(from: url)

            visits.append(PageVisit(
                id: "safari-page-\(visitTime)-\(url.hashValue)",
                url: url,
                path: path,
                title: title.isEmpty ? path : title,
                visitTime: date,
                durationSeconds: nil,
                browser: .safari
            ))
        }
        return visits
    }

    // MARK: - Chromium page visits for domain

    private func fetchPageVisitsFromChromium(
        browser: BrowserSource, domain: String, startDate: Date, endDate: Date
    ) throws -> [PageVisit] {
        let db = try getCachedDatabase(for: browser)

        let startChrome = (startDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond
        let endChrome = (endDate.timeIntervalSince1970 + Self.chromiumEpochOffset) * Self.chromiumMicrosPerSecond

        let sql = """
        SELECT u.url, u.title, v.visit_time, v.visit_duration
        FROM visits v
        JOIN urls u ON u.id = v.url
        WHERE v.visit_time >= ?1 AND v.visit_time <= ?2
        ORDER BY v.visit_time DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: browser.rawValue, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, startChrome)
        sqlite3_bind_double(statement, 2, endChrome)

        var visits: [PageVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = Self.columnText(statement, 0) ?? ""
            let title = Self.columnText(statement, 1) ?? ""
            let visitTimeMicros = sqlite3_column_int64(statement, 2)
            let durationMicros = sqlite3_column_int64(statement, 3)

            // Filter by domain in Swift
            guard Self.matchesDomain(url, domain: domain) else { continue }

            let unixTimestamp = (Double(visitTimeMicros) / Self.chromiumMicrosPerSecond) - Self.chromiumEpochOffset
            let date = Date(timeIntervalSince1970: unixTimestamp)
            let duration = durationMicros > 0 ? Double(durationMicros) / Self.chromiumMicrosPerSecond : nil
            let path = Self.extractPath(from: url)

            visits.append(PageVisit(
                id: "\(browser.rawValue.lowercased())-page-\(visitTimeMicros)-\(url.hashValue)",
                url: url,
                path: path,
                title: title.isEmpty ? path : title,
                visitTime: date,
                durationSeconds: duration,
                browser: browser
            ))
        }
        return visits
    }

    // MARK: - Firefox page visits for domain

    private func fetchPageVisitsFromFirefox(
        domain: String, startDate: Date, endDate: Date
    ) throws -> [PageVisit] {
        var visits: [PageVisit] = []
        for db in try getCachedDatabases(for: .firefox) {
            visits.append(contentsOf: try fetchPageVisitsFromFirefoxDatabase(
                db,
                domain: domain,
                startDate: startDate,
                endDate: endDate
            ))
        }
        return visits.sorted { $0.visitTime > $1.visitTime }
    }

    private func fetchPageVisitsFromFirefoxDatabase(
        _ db: OpaquePointer,
        domain: String,
        startDate: Date,
        endDate: Date
    ) throws -> [PageVisit] {
        let startFirefox = Int64(startDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)
        let endFirefox = Int64(endDate.timeIntervalSince1970 * Self.firefoxMicrosPerSecond)

        let sql = """
        SELECT p.url, p.title, v.visit_date
        FROM moz_historyvisits v
        JOIN moz_places p ON p.id = v.place_id
        WHERE v.visit_date >= ?1 AND v.visit_date <= ?2
          AND IFNULL(p.hidden, 0) = 0
        ORDER BY v.visit_date DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw BrowsingHistoryError.sqlite(path: "Firefox", message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, startFirefox)
        sqlite3_bind_int64(statement, 2, endFirefox)

        var visits: [PageVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let url = Self.sanitizeURL(Self.columnText(statement, 0) ?? "") else { continue }
            let title = Self.columnText(statement, 1) ?? ""
            let visitTimeMicros = sqlite3_column_int64(statement, 2)

            // Filter by domain in Swift
            guard Self.matchesDomain(url, domain: domain) else { continue }

            let date = Date(timeIntervalSince1970: Double(visitTimeMicros) / Self.firefoxMicrosPerSecond)
            let path = Self.extractPath(from: url)

            visits.append(PageVisit(
                id: "firefox-page-\(visitTimeMicros)-\(url.hashValue)",
                url: url,
                path: path,
                title: title.isEmpty ? path : title,
                visitTime: date,
                durationSeconds: nil,
                browser: .firefox
            ))
        }
        return visits
    }

    // MARK: - SQLite helpers

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cStr)
    }
}
