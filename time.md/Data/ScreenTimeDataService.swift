import Darwin
import Foundation
import SQLite3

/// Returns the real user home directory, bypassing the sandbox container.
/// In a sandboxed app `NSHomeDirectory()` returns the container path;
/// this function uses POSIX `getpwuid` to get the actual `/Users/<name>`.
nonisolated func realHomeDirectory() -> URL {
    if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
    }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
}

struct ScreenTimeSnapshotRollupRow: Sendable, Equatable {
    let day: String
    let hour: Int
    let appName: String
    let totalSeconds: Double
    let sessionCount: Int
}

protocol ScreenTimeDataServing: Sendable {
    // Screen-level composite APIs keep high-traffic views from opening many
    // SQLite connections and reinstalling temp category mappings per section.
    func fetchOverviewData(filters: FilterSnapshot, topAppsLimit: Int) async throws -> OverviewScreenData
    func fetchDashboardComposite(filters: FilterSnapshot, topAppsLimit: Int) async throws -> DashboardCompositeData
    func fetchReportData(filters: FilterSnapshot, topAppsLimit: Int, topCategoriesLimit: Int) async throws -> ReportScreenData
    func fetchTrendData(filters: FilterSnapshot, topN: Int) async throws -> TrendScreenData
    func fetchCalendarMonthData(filters: FilterSnapshot, topN: Int) async throws -> CalendarMonthData
    func fetchCalendarWeekData(weekStart: Date) async throws -> CalendarWeekData
    func fetchDetailsData(filters: FilterSnapshot, selectedApp: String?, sessionLimit: Int) async throws -> DetailsScreenData

    func fetchDashboardSummary(filters: FilterSnapshot) async throws -> DashboardSummary
    func fetchTrend(filters: FilterSnapshot) async throws -> [TrendPoint]
    func fetchDailyAppBreakdown(filters: FilterSnapshot, topN: Int) async throws -> [DailyAppBreakdown]
    func fetchTopApps(filters: FilterSnapshot, limit: Int) async throws -> [AppUsageSummary]
    func fetchTopCategories(filters: FilterSnapshot, limit: Int) async throws -> [CategoryUsageSummary]
    func fetchSessionBuckets(filters: FilterSnapshot) async throws -> [SessionBucket]
    func fetchHeatmap(filters: FilterSnapshot) async throws -> [HeatmapCell]
    func fetchHeatmapCellAppUsage(filters: FilterSnapshot) async throws -> [HeatmapCellAppUsage]
    func fetchFocusDays(filters: FilterSnapshot) async throws -> [FocusDay]
    func fetchHourlyAppUsage(for date: Date) async throws -> [HourlyAppUsage]
    func fetchCategoryMappings() async throws -> [AppCategoryMapping]
    func saveCategoryMapping(appName: String, category: String) async throws
    func deleteCategoryMapping(appName: String) async throws

    // Phase 2 — enriched overview
    func fetchTodaySummary() async throws -> TodaySummary
    func fetchPeriodSummary(filters: FilterSnapshot) async throws -> PeriodSummary
    func fetchRecentSparkline(days: Int) async throws -> [SparklinePoint]
    func fetchSparkline(filters: FilterSnapshot) async throws -> [SparklinePoint]
    func fetchLongestSession(filters: FilterSnapshot) async throws -> LongestSession?

    // Phase 4 — analytics engine
    func fetchContextSwitchRate(filters: FilterSnapshot) async throws -> [ContextSwitchPoint]
    func fetchAppTransitions(filters: FilterSnapshot, limit: Int) async throws -> [AppTransition]
    func fetchWeekdayAverages(filters: FilterSnapshot) async throws -> [WeekdayAverage]
    func fetchPeriodComparison(current: FilterSnapshot, previous: FilterSnapshot) async throws -> PeriodDelta
    func generateInsights(filters: FilterSnapshot) async throws -> [Insight]

    // Phase E1 — raw session export
    func fetchRawSessions(filters: FilterSnapshot) async throws -> [RawSession]
    func fetchRawSessionCount(filters: FilterSnapshot) async throws -> Int

    // Input tracking — opt-in keystroke + cursor capture
    func fetchCursorHeatmap(
        startDate: Date,
        endDate: Date,
        screenID: Int?,
        bundleID: String?
    ) async throws -> [CursorHeatmapBin]

    func fetchTopTypedWords(
        startDate: Date,
        endDate: Date,
        bundleID: String?,
        limit: Int
    ) async throws -> [TypedWordRow]

    func fetchTopTypedKeys(
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [TypedKeyRow]

    func fetchTypingIntensity(
        startDate: Date,
        endDate: Date,
        granularity: IntensityGranularity
    ) async throws -> [IntensityPoint]

    func fetchInputTrackingScreenIDs(
        startDate: Date,
        endDate: Date
    ) async throws -> [Int]

    func fetchInputTrackingBundleIDs(
        startDate: Date,
        endDate: Date
    ) async throws -> [String]

    func fetchClickLocations(
        startDate: Date,
        endDate: Date,
        screenID: Int?,
        bundleID: String?,
        limit: Int
    ) async throws -> [ClickLocation]

    func fetchRawKeystrokeEvents(
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [RawKeystrokeEvent]

    func fetchRawKeystrokeEventCount(
        startDate: Date,
        endDate: Date
    ) async throws -> Int

    func fetchRawMouseEvents(
        startDate: Date,
        endDate: Date,
        limit: Int
    ) async throws -> [RawMouseEvent]

    func fetchRawMouseEventCount(
        startDate: Date,
        endDate: Date
    ) async throws -> Int
}

enum ScreenTimeDataError: LocalizedError, Sendable {
    case databaseNotFound(searchedPaths: [String])
    case permissionDenied(path: String)
    case schemaMismatch(path: String, details: String)
    case sqlite(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .databaseNotFound(searchedPaths):
            if let overrideEntry = searchedPaths.first(where: { $0.hasPrefix("SCREENTIME_DB_PATH=") }) {
                return "SCREENTIME_DB_PATH is set, but no readable SQLite file exists at \(overrideEntry.replacingOccurrences(of: "SCREENTIME_DB_PATH=", with: ""))."
            }

            let joined = searchedPaths.joined(separator: "\n")
            return "Could not find a Screen Time SQLite database. Searched:\n\(joined)"
        case let .permissionDenied(path):
            return "Permission denied while accessing \(path)."
        case let .schemaMismatch(path, details):
            return "Unsupported database schema at \(path). \(details)"
        case let .sqlite(path, message):
            return "SQLite error for \(path): \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .databaseNotFound(searchedPaths):
            if searchedPaths.contains(where: { $0.hasPrefix("SCREENTIME_DB_PATH=") }) {
                return "Update SCREENTIME_DB_PATH to a valid screentime.db file, or unset it to use automatic discovery."
            }
            return "Set SCREENTIME_DB_PATH to a valid normalized screentime.db."
        case .permissionDenied:
            return "Grant Full Disk Access for local development, or select an accessible DB file in Settings."
        case .schemaMismatch:
            return "Use a normalized screentime.db with a usage table."
        case .sqlite:
            return "Verify the database file is valid and not corrupted."
        }
    }

    static func message(for error: Error) -> String {
        if let dataError = error as? ScreenTimeDataError {
            if let suggestion = dataError.recoverySuggestion {
                return "\(dataError.localizedDescription)\n\n\(suggestion)"
            }
            return dataError.localizedDescription
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

struct SQLiteScreenTimeDataService: ScreenTimeDataServing {
    private let overridePath: String?

    init(pathOverride: String? = nil) {
        self.overridePath = pathOverride ?? Self.environmentOverrideIfExplicitlyEnabled()
    }

    private static func environmentOverrideIfExplicitlyEnabled() -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TIMEMD_ALLOW_SCREENTIME_DB_PATH"] == "1" else {
            return nil
        }
        return environment["SCREENTIME_DB_PATH"]
    }

    func fetchOverviewData(filters: FilterSnapshot, topAppsLimit: Int) async throws -> OverviewScreenData {
        let limit = max(topAppsLimit, 1)

        return try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            let calendar = Calendar.current
            let currentStats = try Self.fetchUsageStatsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap,
                includeWebUsage: false
            )

            let previousPeriodFilters = Self.previousPeriodFilters(for: filters, calendar: calendar)
            let previousPeriodStats = try Self.fetchUsageStatsNormalized(
                db: context.db,
                filters: previousPeriodFilters,
                hasCategoryMap: context.hasCategoryMap,
                includeWebUsage: false
            )

            if currentStats.sessionCount == 0 || currentStats.totalSeconds <= 0 {
                let periodSummary = PeriodSummary(
                    granularity: filters.granularity,
                    totalSeconds: 0,
                    previousTotalSeconds: previousPeriodStats.totalSeconds,
                    peakHour: 0,
                    peakHourSeconds: 0,
                    appsUsedCount: 0,
                    topAppName: "None",
                    topAppSeconds: 0
                )

                let periodDelta: PeriodDelta?
                if let previousComparisonFilters = Self.previousComparisonFilters(for: filters, calendar: calendar) {
                    let previousStats = try Self.fetchUsageStatsNormalized(
                        db: context.db,
                        filters: previousComparisonFilters,
                        hasCategoryMap: context.hasCategoryMap,
                        includeWebUsage: false
                    )
                    periodDelta = Self.buildPeriodDelta(
                        currentApps: [],
                        previousApps: [],
                        currentTotal: 0,
                        previousTotal: previousStats.totalSeconds,
                        currentAppsUsed: 0,
                        previousAppsUsed: previousStats.uniqueAppCount
                    )
                } else {
                    periodDelta = nil
                }

                return OverviewScreenData(
                    topApps: [],
                    hourlyUsage: [],
                    periodSummary: periodSummary,
                    periodDelta: periodDelta
                )
            }

            let currentApps = try Self.fetchTopAppsNormalized(
                db: context.db,
                filters: filters,
                limit: limit,
                hasCategoryMap: context.hasCategoryMap
            )
            let heatmap = try Self.fetchHeatmapNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let hourTotals = Dictionary(grouping: heatmap, by: { $0.hour })
                .mapValues { cells in cells.reduce(0.0) { $0 + $1.totalSeconds } }
            let peak = hourTotals.max(by: { $0.value < $1.value })
            let topApp = currentApps.first

            let periodSummary = PeriodSummary(
                granularity: filters.granularity,
                totalSeconds: currentStats.totalSeconds,
                previousTotalSeconds: previousPeriodStats.totalSeconds,
                peakHour: peak?.key ?? 0,
                peakHourSeconds: peak?.value ?? 0,
                appsUsedCount: currentStats.uniqueAppCount,
                topAppName: topApp?.appName ?? "None",
                topAppSeconds: topApp?.totalSeconds ?? 0
            )

            let dayStart = calendar.startOfDay(for: filters.startDate)
            let hourlyFilters = FilterSnapshot(
                startDate: dayStart,
                endDate: dayStart,
                granularity: .day,
                selectedApps: filters.selectedApps,
                selectedCategories: filters.selectedCategories,
                selectedHeatmapCells: []
            )
            let hourlyUsage = try Self.fetchHourlyAppUsageNormalized(
                db: context.db,
                filters: hourlyFilters,
                hasCategoryMap: context.hasCategoryMap
            )

            let periodDelta: PeriodDelta?
            if let previousComparisonFilters = Self.previousComparisonFilters(for: filters, calendar: calendar) {
                let previousStats = try Self.fetchUsageStatsNormalized(
                    db: context.db,
                    filters: previousComparisonFilters,
                    hasCategoryMap: context.hasCategoryMap,
                    includeWebUsage: false
                )
                periodDelta = Self.buildPeriodDelta(
                    currentApps: [],
                    previousApps: [],
                    currentTotal: currentStats.totalSeconds,
                    previousTotal: previousStats.totalSeconds,
                    currentAppsUsed: currentStats.uniqueAppCount,
                    previousAppsUsed: previousStats.uniqueAppCount
                )
            } else {
                periodDelta = nil
            }

            return OverviewScreenData(
                topApps: currentApps,
                hourlyUsage: hourlyUsage,
                periodSummary: periodSummary,
                periodDelta: periodDelta
            )
        }
    }

    func fetchDashboardComposite(filters: FilterSnapshot, topAppsLimit: Int) async throws -> DashboardCompositeData {
        let limit = max(topAppsLimit, 1)

        return try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            let focusRows = try Self.fetchFocusDayRowsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let focusDays = Self.completeFocusDays(rows: focusRows, filters: filters)
            let summary = Self.dashboardSummary(from: focusDays)

            let topApps = try Self.fetchTopAppsNormalized(
                db: context.db,
                filters: filters,
                limit: limit,
                hasCategoryMap: context.hasCategoryMap
            )
            let periodSummary = try Self.buildPeriodSummary(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap,
                currentApps: topApps
            )
            let dailyTotals = try Self.fetchDailyTotalsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let sparklinePoints = Self.aggregateTrend(dailyTotals: dailyTotals, filters: filters)
                .map { SparklinePoint(date: $0.date, totalSeconds: $0.totalSeconds) }

            let hourlyTrendPoints = try Self.hourlySparklinePointsIfNeeded(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )

            let fetchedHeatmap = try Self.fetchHeatmapNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let heatmapCells = Self.completeHeatmap(cells: fetchedHeatmap)
            let heatmapMax = heatmapCells.map(\.totalSeconds).max() ?? 0

            let longest = try Self.fetchLongestSessionNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let buckets = try Self.fetchSessionBucketsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let weekdayAverages = try Self.fetchWeekdayAveragesNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let insights = Self.buildInsights(
                summary: summary,
                topApps: topApps,
                buckets: buckets,
                longest: longest,
                weekdayAvgs: weekdayAverages
            )
            let periodDelta = try Self.fetchPeriodDeltaNormalized(
                db: context.db,
                current: filters,
                hasCategoryMap: context.hasCategoryMap,
                currentStats: Self.fetchUsageStatsNormalized(
                    db: context.db,
                    filters: filters,
                    hasCategoryMap: context.hasCategoryMap,
                    includeWebUsage: false
                )
            )

            return DashboardCompositeData(
                summary: summary,
                topApps: topApps,
                longestSession: longest,
                periodSummary: periodSummary,
                sparklinePoints: sparklinePoints,
                hourlyTrendPoints: hourlyTrendPoints,
                heatmapCells: heatmapCells,
                heatmapMax: heatmapMax,
                insights: insights,
                periodDelta: periodDelta
            )
        }
    }

    func fetchReportData(filters: FilterSnapshot, topAppsLimit: Int, topCategoriesLimit: Int) async throws -> ReportScreenData {
        let appLimit = max(topAppsLimit, 1)
        let categoryLimit = max(topCategoriesLimit, 1)

        return try await runQuery { context in
            let topApps = try Self.fetchTopAppsNormalized(
                db: context.db,
                filters: filters,
                limit: appLimit,
                hasCategoryMap: context.hasCategoryMap
            )
            let topCategories = try Self.fetchTopCategoriesNormalized(
                db: context.db,
                filters: filters,
                limit: categoryLimit,
                hasCategoryMap: context.hasCategoryMap
            )
            let dailyTotals = try Self.fetchDailyTotalsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let trendPoints = Self.aggregateTrend(dailyTotals: dailyTotals, filters: filters)
            let periodSummary = try Self.buildPeriodSummary(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap,
                currentApps: topApps
            )
            let weekdayAverages = try Self.fetchWeekdayAveragesNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )

            return ReportScreenData(
                topApps: topApps,
                topCategories: topCategories,
                trendPoints: trendPoints,
                periodSummary: periodSummary,
                weekdayAverages: weekdayAverages
            )
        }
    }

    func fetchTrendData(filters: FilterSnapshot, topN: Int) async throws -> TrendScreenData {
        let appLimit = max(topN, 1)

        return try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            if filters.granularity == .day {
                let hourlyData = try Self.fetchHourlyAppUsageNormalized(
                    db: context.db,
                    filters: filters,
                    hasCategoryMap: context.hasCategoryMap
                )
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: filters.startDate)
                let hourlyTotals = Dictionary(grouping: hourlyData, by: { $0.hour })
                    .mapValues { rows in rows.reduce(0.0) { $0 + $1.totalSeconds } }
                let trend = (0..<24).compactMap { hour -> TrendPoint? in
                    guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) else { return nil }
                    return TrendPoint(date: hourDate, totalSeconds: hourlyTotals[hour, default: 0])
                }
                let breakdown = hourlyData.compactMap { entry -> DailyAppBreakdown? in
                    guard let hourDate = calendar.date(bySettingHour: entry.hour, minute: 0, second: 0, of: dayStart) else { return nil }
                    return DailyAppBreakdown(date: hourDate, appName: entry.appName, totalSeconds: entry.totalSeconds)
                }
                return TrendScreenData(trend: trend, dailyBreakdown: breakdown, hourlyAppData: hourlyData)
            }

            let dailyTotals = try Self.fetchDailyTotalsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let trend = Self.aggregateTrend(dailyTotals: dailyTotals, filters: filters)
            let dailyAppRows = try Self.fetchDailyAppRowsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let breakdown = Self.aggregateDailyAppBreakdown(rawRows: dailyAppRows, filters: filters, topN: appLimit)
            return TrendScreenData(trend: trend, dailyBreakdown: breakdown, hourlyAppData: [])
        }
    }

    func fetchCalendarMonthData(filters: FilterSnapshot, topN: Int) async throws -> CalendarMonthData {
        let appLimit = max(topN, 1)

        return try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            let focusRows = try Self.fetchFocusDayRowsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let focusDays = Self.completeFocusDays(rows: focusRows, filters: filters)
            var totals: [Date: Double] = [:]
            for day in focusDays {
                totals[Calendar.current.startOfDay(for: day.date)] = day.totalSeconds
            }

            let dailyRows = try Self.fetchDailyAppRowsNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let breakdown = Self.aggregateDailyAppBreakdown(rawRows: dailyRows, filters: filters, topN: appLimit)
            var apps: [Date: [DailyAppBreakdown]] = [:]
            for entry in breakdown {
                let dayStart = Calendar.current.startOfDay(for: entry.date)
                apps[dayStart, default: []].append(entry)
            }
            for key in apps.keys {
                apps[key]?.sort { $0.totalSeconds > $1.totalSeconds }
            }

            return CalendarMonthData(dailyTotals: totals, dailyApps: apps)
        }
    }

    func fetchCalendarWeekData(weekStart: Date) async throws -> CalendarWeekData {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStart)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }

        return try await runQuery(installCategoryMappings: false) { context in
            var hourlyByDay: [Date: [HourlyAppUsage]] = [:]
            var rawSessionsByDay: [Date: [RawSession]] = [:]
            hourlyByDay.reserveCapacity(days.count)
            rawSessionsByDay.reserveCapacity(days.count)

            for day in days {
                let dayStart = calendar.startOfDay(for: day)

                let dayFilters = FilterSnapshot(
                    startDate: dayStart,
                    endDate: dayStart,
                    granularity: .day,
                    selectedApps: [],
                    selectedCategories: [],
                    selectedHeatmapCells: []
                )
                hourlyByDay[dayStart] = try Self.fetchHourlyAppUsageNormalized(
                    db: context.db,
                    filters: dayFilters,
                    hasCategoryMap: context.hasCategoryMap
                )
                rawSessionsByDay[dayStart] = try Self.fetchRawSessionsNormalized(
                    db: context.db,
                    filters: dayFilters,
                    hasCategoryMap: context.hasCategoryMap
                )
            }

            return CalendarWeekData(hourlyByDay: hourlyByDay, rawSessionsByDay: rawSessionsByDay)
        }
    }

    func fetchDetailsData(filters: FilterSnapshot, selectedApp: String?, sessionLimit: Int) async throws -> DetailsScreenData {
        let normalizedSelectedApp = selectedApp?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedAppFilter = normalizedSelectedApp?.isEmpty == false ? normalizedSelectedApp : nil
        let limit = max(sessionLimit, 1)

        return try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            let detailFilters = Self.restricting(filters, toApp: selectedAppFilter)
            let sessions = try Self.fetchRawSessionsNormalized(
                db: context.db,
                filters: detailFilters,
                hasCategoryMap: context.hasCategoryMap,
                limit: limit
            )
            let totalSessionCount = try Self.fetchRawSessionCountNormalized(
                db: context.db,
                filters: detailFilters,
                hasCategoryMap: context.hasCategoryMap
            )
            let totalSeconds = try Self.totalUsageSecondsNormalized(
                db: context.db,
                filters: detailFilters,
                hasCategoryMap: context.hasCategoryMap
            )
            let uniqueAppCount = try Self.fetchDistinctAppCountNormalized(
                db: context.db,
                filters: detailFilters,
                hasCategoryMap: context.hasCategoryMap
            )
            let appFilterOptions = try Self.fetchTopAppsNormalized(
                db: context.db,
                filters: filters,
                limit: 50,
                hasCategoryMap: context.hasCategoryMap
            )
            let contextSwitches = try Self.fetchContextSwitchesNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
            let transitions = try Self.fetchAppTransitionsNormalized(
                db: context.db,
                filters: filters,
                limit: 10,
                hasCategoryMap: context.hasCategoryMap
            )

            return DetailsScreenData(
                sessions: sessions,
                totalSessionCount: totalSessionCount,
                totalSeconds: totalSeconds,
                uniqueAppCount: uniqueAppCount,
                appFilterOptions: appFilterOptions,
                contextSwitches: contextSwitches,
                transitions: transitions
            )
        }
    }

    func fetchDashboardSummary(filters: FilterSnapshot) async throws -> DashboardSummary {
        let focusDays = try await fetchFocusDays(filters: filters)

        let totalSeconds = focusDays.reduce(0) { $0 + $1.totalSeconds }
        let averageDailySeconds = focusDays.isEmpty ? 0 : totalSeconds / Double(focusDays.count)
        let focusBlocks = focusDays.reduce(0) { $0 + $1.focusBlocks }

        return DashboardSummary(
            totalSeconds: totalSeconds,
            averageDailySeconds: averageDailySeconds,
            focusBlocks: focusBlocks
        )
    }

    func fetchTrend(filters: FilterSnapshot) async throws -> [TrendPoint] {
        let dailyTotals = try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchDailyTotalsNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }

        return Self.aggregateTrend(dailyTotals: dailyTotals, filters: filters)
    }

    func fetchDailyAppBreakdown(filters: FilterSnapshot, topN: Int) async throws -> [DailyAppBreakdown] {
        let rawRows = try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchDailyAppRowsNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }

        return Self.aggregateDailyAppBreakdown(rawRows: rawRows, filters: filters, topN: topN)
    }

    func fetchTopApps(filters: FilterSnapshot, limit: Int) async throws -> [AppUsageSummary] {
        guard limit > 0 else { return [] }

        return try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchTopAppsNormalized(db: context.db, filters: filters, limit: limit, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchTopCategories(filters: FilterSnapshot, limit: Int) async throws -> [CategoryUsageSummary] {
        guard limit > 0 else { return [] }

        return try await runQuery { context in
            return try Self.fetchTopCategoriesNormalized(db: context.db, filters: filters, limit: limit, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchSessionBuckets(filters: FilterSnapshot) async throws -> [SessionBucket] {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchSessionBucketsNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchHeatmap(filters: FilterSnapshot) async throws -> [HeatmapCell] {
        let cells = try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchHeatmapNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }

        var byCoordinate = Dictionary(uniqueKeysWithValues: cells.map { (HeatmapCellCoordinate(weekday: $0.weekday, hour: $0.hour), $0.totalSeconds) })
        var completed: [HeatmapCell] = []
        completed.reserveCapacity(7 * 24)

        for weekday in 0..<7 {
            for hour in 0..<24 {
                let coordinate = HeatmapCellCoordinate(weekday: weekday, hour: hour)
                let total = byCoordinate.removeValue(forKey: coordinate) ?? 0
                completed.append(HeatmapCell(weekday: weekday, hour: hour, totalSeconds: total))
            }
        }

        return completed
    }

    func fetchHeatmapCellAppUsage(filters: FilterSnapshot) async throws -> [HeatmapCellAppUsage] {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchHeatmapCellAppUsageNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchFocusDays(filters: FilterSnapshot) async throws -> [FocusDay] {
        let fetchedRows = try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchFocusDayRowsNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: filters.startDate)
        let end = calendar.startOfDay(for: filters.endDate)
        let mapped = Dictionary(uniqueKeysWithValues: fetchedRows.map { ($0.day, $0) })

        var result: [FocusDay] = []
        var cursor = start
        while cursor <= end {
            if let row = mapped[cursor] {
                result.append(FocusDay(date: cursor, focusBlocks: row.focusBlocks, totalSeconds: row.totalSeconds))
            } else {
                result.append(FocusDay(date: cursor, focusBlocks: 0, totalSeconds: 0))
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return result
    }

    func fetchHourlyAppUsage(for date: Date) async throws -> [HourlyAppUsage] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        let filters = FilterSnapshot(
            startDate: dayStart,
            endDate: dayStart,
            granularity: .day,
            selectedApps: [],
            selectedCategories: [],
            selectedHeatmapCells: []
        )

        return try await runQuery(installCategoryMappings: false) { context in
            return try Self.fetchHourlyAppUsageNormalized(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
        }
    }

    func fetchTodaySummary() async throws -> TodaySummary {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        let todayFilters = FilterSnapshot(
            startDate: todayStart, endDate: todayStart,
            granularity: .day, selectedApps: [], selectedCategories: [], selectedHeatmapCells: []
        )
        let yesterdayFilters = FilterSnapshot(
            startDate: yesterdayStart, endDate: yesterdayStart,
            granularity: .day, selectedApps: [], selectedCategories: [], selectedHeatmapCells: []
        )

        return try await runQuery(installCategoryMappings: false) { context in
            let todayStats = try Self.fetchUsageStatsNormalized(
                db: context.db,
                filters: todayFilters,
                hasCategoryMap: context.hasCategoryMap,
                includeWebUsage: false
            )
            let yesterdayStats = try Self.fetchUsageStatsNormalized(
                db: context.db,
                filters: yesterdayFilters,
                hasCategoryMap: context.hasCategoryMap,
                includeWebUsage: false
            )

            guard todayStats.sessionCount > 0, todayStats.totalSeconds > 0 else {
                return TodaySummary(
                    todayTotalSeconds: 0,
                    yesterdayTotalSeconds: yesterdayStats.totalSeconds,
                    peakHour: 0,
                    peakHourSeconds: 0,
                    appsUsedCount: 0,
                    topAppName: "None",
                    topAppSeconds: 0
                )
            }

            let topApp = try Self.fetchTopAppsNormalized(
                db: context.db,
                filters: todayFilters,
                limit: 1,
                hasCategoryMap: context.hasCategoryMap
            ).first
            let hourlyUsage = try Self.fetchHourlyAppUsageNormalized(
                db: context.db,
                filters: todayFilters,
                hasCategoryMap: context.hasCategoryMap
            )
            let hourlyTotals = Dictionary(grouping: hourlyUsage, by: { $0.hour })
                .mapValues { rows in rows.reduce(0.0) { $0 + $1.totalSeconds } }
            let peak = hourlyTotals.max(by: { $0.value < $1.value })

            return TodaySummary(
                todayTotalSeconds: todayStats.totalSeconds,
                yesterdayTotalSeconds: yesterdayStats.totalSeconds,
                peakHour: peak?.key ?? 0,
                peakHourSeconds: peak?.value ?? 0,
                appsUsedCount: todayStats.uniqueAppCount,
                topAppName: topApp?.appName ?? "None",
                topAppSeconds: topApp?.totalSeconds ?? 0
            )
        }
    }

    func fetchRecentSparkline(days: Int) async throws -> [SparklinePoint] {
        let calendar = Calendar.current
        let endDate = Date.now
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: endDate)) ?? endDate

        let filters = FilterSnapshot(
            startDate: startDate, endDate: endDate,
            granularity: .day, selectedApps: [], selectedCategories: [], selectedHeatmapCells: []
        )

        let trend = try await fetchTrend(filters: filters)
        return trend.map { SparklinePoint(date: $0.date, totalSeconds: $0.totalSeconds) }
    }

    func fetchSparkline(filters: FilterSnapshot) async throws -> [SparklinePoint] {
        let trend = try await fetchTrend(filters: filters)
        return trend.map { SparklinePoint(date: $0.date, totalSeconds: $0.totalSeconds) }
    }

    func fetchPeriodSummary(filters: FilterSnapshot) async throws -> PeriodSummary {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            try Self.buildPeriodSummary(
                db: context.db,
                filters: filters,
                hasCategoryMap: context.hasCategoryMap
            )
        }
    }

    func fetchLongestSession(filters: FilterSnapshot) async throws -> LongestSession? {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchLongestSessionNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }
    }

    // MARK: - Phase 4 — Analytics Engine

    func fetchContextSwitchRate(filters: FilterSnapshot) async throws -> [ContextSwitchPoint] {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchContextSwitchesNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchAppTransitions(filters: FilterSnapshot, limit: Int) async throws -> [AppTransition] {
        guard limit > 0 else { return [] }
        return try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchAppTransitionsNormalized(db: context.db, filters: filters, limit: limit, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchWeekdayAverages(filters: FilterSnapshot) async throws -> [WeekdayAverage] {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchWeekdayAveragesNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchPeriodComparison(current: FilterSnapshot, previous: FilterSnapshot) async throws -> PeriodDelta {
        try await runQuery(installCategoryMappings: !current.selectedCategories.isEmpty || !previous.selectedCategories.isEmpty) { context in
            let currentApps = try Self.fetchTopAppsNormalized(
                db: context.db,
                filters: current,
                limit: 200,
                hasCategoryMap: context.hasCategoryMap
            )
            let previousApps = try Self.fetchTopAppsNormalized(
                db: context.db,
                filters: previous,
                limit: 200,
                hasCategoryMap: context.hasCategoryMap
            )
            let currentStats = try Self.fetchUsageStatsNormalized(
                db: context.db,
                filters: current,
                hasCategoryMap: context.hasCategoryMap,
                includeWebUsage: false
            )
            let previousStats = try Self.fetchUsageStatsNormalized(
                db: context.db,
                filters: previous,
                hasCategoryMap: context.hasCategoryMap,
                includeWebUsage: false
            )
            return Self.buildPeriodDelta(
                currentApps: currentApps,
                previousApps: previousApps,
                currentTotal: currentStats.totalSeconds,
                previousTotal: previousStats.totalSeconds,
                currentAppsUsed: currentStats.uniqueAppCount,
                previousAppsUsed: previousStats.uniqueAppCount
            )
        }
    }

    func generateInsights(filters: FilterSnapshot) async throws -> [Insight] {
        // Gather data in parallel
        async let summaryFetch = fetchDashboardSummary(filters: filters)
        async let topAppsFetch = fetchTopApps(filters: filters, limit: 5)
        async let sessionBucketsFetch = fetchSessionBuckets(filters: filters)
        async let longestFetch = fetchLongestSession(filters: filters)
        async let weekdayAvgFetch = fetchWeekdayAverages(filters: filters)

        let summary = try await summaryFetch
        let topApps = try await topAppsFetch
        let buckets = try await sessionBucketsFetch
        let longest = try await longestFetch
        let weekdayAvgs = try await weekdayAvgFetch

        var insights: [Insight] = []

        // 1. Total screen time
        let totalHours = summary.totalSeconds / 3600
        insights.append(Insight(
            icon: "clock.fill",
            text: String(format: "Total screen time: %.1fh across the selected period", totalHours),
            sentiment: .neutral
        ))

        // 2. Daily average
        let avgHours = summary.averageDailySeconds / 3600
        let sentiment: InsightSentiment = avgHours < 4 ? .positive : avgHours > 6 ? .negative : .neutral
        insights.append(Insight(
            icon: "chart.line.downtrend.xyaxis",
            text: String(format: "Your daily average is %.1fh", avgHours),
            sentiment: sentiment
        ))

        // 3. Top app
        if let top = topApps.first {
            let pct = summary.totalSeconds > 0 ? (top.totalSeconds / summary.totalSeconds) * 100 : 0
            insights.append(Insight(
                icon: "star.fill",
                text: String(format: "%@ accounts for %.0f%% of your screen time", top.appName, pct),
                sentiment: .neutral
            ))
        }

        // 4. Apps used count
        insights.append(Insight(
            icon: "square.grid.3x3.fill",
            text: "You used \(topApps.count > 4 ? "5+" : "\(topApps.count)") different apps",
            sentiment: .neutral
        ))

        // 5. Longest session
        if let longest {
            insights.append(Insight(
                icon: "timer",
                text: String(format: "Longest session: %@ in %@", DurationFormatter.short(longest.durationSeconds), longest.appName),
                sentiment: longest.durationSeconds > 7200 ? .negative : .neutral
            ))
        }

        // 6. Most common session length
        if let peakBucket = buckets.max(by: { $0.sessionCount < $1.sessionCount }) {
            insights.append(Insight(
                icon: "chart.bar.fill",
                text: "Most sessions are \(peakBucket.label) long (\(peakBucket.sessionCount) sessions)",
                sentiment: .neutral
            ))
        }

        // 7. Busiest weekday
        if let busiest = weekdayAvgs.max(by: { $0.averageSeconds < $1.averageSeconds }) {
            let dayNames = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
            let dayName = busiest.weekday < dayNames.count ? dayNames[busiest.weekday] : "Day \(busiest.weekday)"
            insights.append(Insight(
                icon: "calendar",
                text: String(format: "%@ are your busiest — %.1fh avg, mostly %@", dayName, busiest.averageSeconds / 3600, busiest.topApp),
                sentiment: .neutral
            ))
        }

        // 9. Quietest weekday
        if let quietest = weekdayAvgs.min(by: { $0.averageSeconds < $1.averageSeconds }),
           weekdayAvgs.count > 1 {
            let dayNames = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
            let dayName = quietest.weekday < dayNames.count ? dayNames[quietest.weekday] : "Day \(quietest.weekday)"
            insights.append(Insight(
                icon: "moon.fill",
                text: String(format: "%@ are your lightest — %.1fh avg", dayName, quietest.averageSeconds / 3600),
                sentiment: .positive
            ))
        }

        return insights
    }

    // MARK: - Auto-save snapshot rollups

    func fetchSnapshotRollupRows(startDate: Date, endDate: Date) async throws -> [ScreenTimeSnapshotRollupRow] {
        try await runQuery(installCategoryMappings: false, label: "fetchSnapshotRollupRows(startDate:endDate:)") { context in
            guard Self.usageHourlyRollupsReady(db: context.db) else {
                throw ScreenTimeDataError.schemaMismatch(
                    path: context.sourceURL.path,
                    details: "Usage hourly rollups are not ready."
                )
            }

            let calendar = Calendar.current
            let start = calendar.startOfDay(for: startDate)
            let endStart = calendar.startOfDay(for: endDate)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: endStart) ?? endStart
            let range = (
                startISO: Self.isoDateTime(start),
                endExclusiveISO: Self.isoDateTime(endExclusive)
            )
            let scope = try Self.usageRollupScope(db: context.db, range: range)
            let dayStart = String(range.startISO.prefix(10))
            let dayEndExclusive = String(range.endExclusiveISO.prefix(10))

            let sql = """
            SELECT
                day,
                hour,
                app_name,
                SUM(total_seconds) AS total_seconds,
                SUM(session_count) AS session_count
            FROM usage_hourly_app_rollups
            WHERE rollup_scope = ?
              AND day >= ?
              AND day < ?
              AND stream_type IN ('app_usage', 'web_usage', 'media_usage')
            GROUP BY day, hour, app_name
            ORDER BY day ASC, hour ASC, total_seconds DESC
            """

            return try SQLiteRunner.query(db: context.db, sql: sql, parameters: [
                .text(scope),
                .text(dayStart),
                .text(dayEndExclusive)
            ]) { statement in
                ScreenTimeSnapshotRollupRow(
                    day: SQLiteRunner.columnText(statement, index: 0) ?? "",
                    hour: Int(SQLiteRunner.columnInt(statement, index: 1)),
                    appName: SQLiteRunner.columnText(statement, index: 2) ?? "Unknown",
                    totalSeconds: SQLiteRunner.columnDouble(statement, index: 3),
                    sessionCount: Int(SQLiteRunner.columnInt(statement, index: 4))
                )
            }
        }
    }

    // MARK: - Phase E1 — Raw Session Export

    func fetchRawSessions(filters: FilterSnapshot) async throws -> [RawSession] {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchRawSessionsNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchRawSessionCount(filters: FilterSnapshot) async throws -> Int {
        try await runQuery(installCategoryMappings: !filters.selectedCategories.isEmpty) { context in
            return try Self.fetchRawSessionCountNormalized(db: context.db, filters: filters, hasCategoryMap: context.hasCategoryMap)
        }
    }

    func fetchCategoryMappings() async throws -> [AppCategoryMapping] {
        try await Task.detached(priority: .userInitiated) {
            try CategoryMappingStore.fetchAll()
        }.value
    }

    func saveCategoryMapping(appName: String, category: String) async throws {
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedAppName.isEmpty else {
            return
        }

        if normalizedCategory.isEmpty {
            try await deleteCategoryMapping(appName: normalizedAppName)
            return
        }

        try await Task.detached(priority: .userInitiated) {
            try CategoryMappingStore.upsert(appName: normalizedAppName, category: normalizedCategory)
        }.value
    }

    func deleteCategoryMapping(appName: String) async throws {
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAppName.isEmpty else {
            return
        }

        try await Task.detached(priority: .userInitiated) {
            try CategoryMappingStore.delete(appName: normalizedAppName)
        }.value
    }

    private func runQuery<T: Sendable>(
        installCategoryMappings: Bool = true,
        label: String = #function,
        _ operation: @escaping @Sendable (SQLiteConnectionContext) throws -> T
    ) async throws -> T {
        let overridePath = self.overridePath

        return try await Task.detached(priority: .userInitiated) {
            let trace = PerformanceTrace.begin(
                "SQLite query",
                metadata: "caller=\(label) categoryMap=\(installCategoryMappings)"
            )
            defer {
                PerformanceTrace.end(
                    "SQLite query",
                    startedAt: trace,
                    metadata: "caller=\(label)"
                )
            }

            // Note: HistoryStore.syncIfNeeded() is now called at app startup and on a
            // 15-minute timer (see TimeMdApp), so we don't need to check before every
            // query. This reduces lock contention when multiple queries run in parallel.

            let context = try Self.openConnectionContext(
                pathOverride: overridePath,
                installCategoryMappings: installCategoryMappings
            )
            defer { context.close() }
            return try operation(context)
        }.value
    }
}

// MARK: - Query implementation

private extension SQLiteScreenTimeDataService {
    static func fetchTopAppsNormalized(db: OpaquePointer, filters: FilterSnapshot, limit: Int, hasCategoryMap: Bool) throws -> [AppUsageSummary] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            u.app_name,
            SUM(u.duration_seconds) AS total_seconds,
            COUNT(*) AS session_count
        FROM usage u
        \(join)
        WHERE \(filter.whereClause) AND u.stream_type != 'web_usage'
        GROUP BY u.app_name
        ORDER BY total_seconds DESC
        LIMIT ?
        """

        var parameters = filter.parameters
        parameters.append(.int(Int64(limit)))

        return try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            AppUsageSummary(
                appName: SQLiteRunner.columnText(statement, index: 0) ?? "Unknown",
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 1),
                sessionCount: Int(SQLiteRunner.columnInt(statement, index: 2))
            )
        }
    }

    static func fetchTopCategoriesNormalized(db: OpaquePointer, filters: FilterSnapshot, limit: Int, hasCategoryMap: Bool) throws -> [CategoryUsageSummary] {
        guard hasCategoryMap else {
            let total = try totalUsageSecondsNormalized(db: db, filters: filters, hasCategoryMap: false)
            if !filters.selectedCategories.isEmpty, !filters.selectedCategories.contains("Uncategorized") {
                return []
            }
            return total > 0 ? [CategoryUsageSummary(category: "Uncategorized", totalSeconds: total)] : []
        }

        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: true, includeCategorySelection: true, db: db)

        let sql = """
        SELECT
            COALESCE(m.category, 'Uncategorized') AS category,
            SUM(u.duration_seconds) AS total_seconds
        FROM usage u
        LEFT JOIN app_category_map m ON m.app_name = u.app_name
        WHERE \(filter.whereClause)
        GROUP BY category
        ORDER BY total_seconds DESC
        LIMIT ?
        """

        var parameters = filter.parameters
        parameters.append(.int(Int64(limit)))

        return try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            CategoryUsageSummary(
                category: SQLiteRunner.columnText(statement, index: 0) ?? "Uncategorized",
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 1)
            )
        }
    }

    static func fetchSessionBucketsNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [SessionBucket] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            CASE
                WHEN u.duration_seconds < 60 THEN '<1m'
                WHEN u.duration_seconds < 300 THEN '1–5m'
                WHEN u.duration_seconds < 900 THEN '5–15m'
                WHEN u.duration_seconds < 1800 THEN '15–30m'
                WHEN u.duration_seconds < 3600 THEN '30–60m'
                ELSE '60m+'
            END AS bucket,
            COUNT(*) AS sessions,
            CASE
                WHEN u.duration_seconds < 60 THEN 0
                WHEN u.duration_seconds < 300 THEN 1
                WHEN u.duration_seconds < 900 THEN 2
                WHEN u.duration_seconds < 1800 THEN 3
                WHEN u.duration_seconds < 3600 THEN 4
                ELSE 5
            END AS sort_order
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        GROUP BY bucket, sort_order
        ORDER BY sort_order
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            SessionBucket(
                label: SQLiteRunner.columnText(statement, index: 0) ?? "Unknown",
                sessionCount: Int(SQLiteRunner.columnInt(statement, index: 1))
            )
        }
    }

    static func fetchHeatmapNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [HeatmapCell] {
        if canUseUsageHourlyRollups(filters: filters, db: db) {
            return try fetchHeatmapFromRollups(db: db, filters: filters)
        }

        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            CAST(strftime('%w', u.start_time) AS INTEGER) AS weekday,
            CAST(strftime('%H', u.start_time) AS INTEGER) AS hour,
            SUM(u.duration_seconds) AS total_seconds
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        GROUP BY weekday, hour
        ORDER BY weekday, hour
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            HeatmapCell(
                weekday: Int(SQLiteRunner.columnInt(statement, index: 0)),
                hour: Int(SQLiteRunner.columnInt(statement, index: 1)),
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 2)
            )
        }
    }

    static func fetchHeatmapFromRollups(db: OpaquePointer, filters: FilterSnapshot) throws -> [HeatmapCell] {
        let range = normalizedDateRange(filters: filters)
        let dayStart = String(range.startISO.prefix(10))
        let dayEndExclusive = String(range.endExclusiveISO.prefix(10))
        let scope = try usageRollupScope(db: db, range: range)

        var conditions = [
            "rollup_scope = ?",
            "day >= ?",
            "day < ?",
            "stream_type IN ('app_usage', 'web_usage', 'media_usage')"
        ]
        var parameters: [SQLiteBinding] = [
            .text(scope),
            .text(dayStart),
            .text(dayEndExclusive)
        ]

        if !filters.selectedApps.isEmpty {
            let sortedApps = filters.selectedApps.sorted()
            conditions.append("app_name IN (\(placeholders(count: sortedApps.count)))")
            parameters.append(contentsOf: sortedApps.map { .text($0) })
        }

        let sql = """
        SELECT
            CAST(strftime('%w', day) AS INTEGER) AS weekday,
            hour,
            SUM(total_seconds) AS total_seconds
        FROM usage_hourly_app_rollups
        WHERE \(conditions.joined(separator: " AND "))
        GROUP BY weekday, hour
        ORDER BY weekday, hour
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            HeatmapCell(
                weekday: Int(SQLiteRunner.columnInt(statement, index: 0)),
                hour: Int(SQLiteRunner.columnInt(statement, index: 1)),
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 2)
            )
        }
    }

    static func fetchHeatmapCellAppUsageNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [HeatmapCellAppUsage] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            CAST(strftime('%w', u.start_time) AS INTEGER) AS weekday,
            CAST(strftime('%H', u.start_time) AS INTEGER) AS hour,
            u.app_name,
            SUM(u.duration_seconds) AS total_seconds
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        GROUP BY weekday, hour, u.app_name
        ORDER BY weekday, hour, total_seconds DESC
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            HeatmapCellAppUsage(
                weekday: Int(SQLiteRunner.columnInt(statement, index: 0)),
                hour: Int(SQLiteRunner.columnInt(statement, index: 1)),
                appName: SQLiteRunner.columnText(statement, index: 2) ?? "Unknown",
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 3)
            )
        }
    }

    static func fetchFocusDayRowsNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [FocusDayRow] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            date(u.start_time) AS day,
            SUM(u.duration_seconds) AS total_seconds,
            SUM(CASE WHEN u.duration_seconds >= 1500 THEN 1 ELSE 0 END) AS focus_blocks
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        GROUP BY day
        ORDER BY day
        """

        return try focusRowsFromQuery(db: db, sql: sql, parameters: filter.parameters)
    }

    static func fetchHourlyAppUsageNormalized(
        db: OpaquePointer,
        filters: FilterSnapshot,
        hasCategoryMap: Bool
    ) throws -> [HourlyAppUsage] {
        if canUseUsageHourlyRollups(filters: filters, db: db) {
            return try fetchHourlyAppUsageFromRollups(db: db, filters: filters)
        }

        let filter = try normalizedFilter(
            filters: filters,
            alias: "u",
            hasCategoryMap: hasCategoryMap,
            includeCategorySelection: true,
            db: db
        )
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            CAST(strftime('%H', u.start_time) AS INTEGER) AS hour,
            u.app_name,
            SUM(u.duration_seconds) AS total_seconds
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        GROUP BY hour, u.app_name
        ORDER BY hour, total_seconds DESC
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            HourlyAppUsage(
                hour: Int(SQLiteRunner.columnInt(statement, index: 0)),
                appName: SQLiteRunner.columnText(statement, index: 1) ?? "Unknown",
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 2)
            )
        }
    }

    static func canUseUsageHourlyRollups(filters: FilterSnapshot, db: OpaquePointer) -> Bool {
        filters.selectedCategories.isEmpty
            && filters.selectedHeatmapCells.isEmpty
            && !filters.hasAdvancedFilters
            && usageHourlyRollupsReady(db: db)
    }

    static func usageHourlyRollupsReady(db: OpaquePointer) -> Bool {
        guard tableExists(db: db, table: "usage_hourly_app_rollups"),
              tableExists(db: db, table: "usage_rollup_meta") else {
            return false
        }

        do {
            let rows: [Int] = try SQLiteRunner.query(
                db: db,
                sql: "SELECT 1 FROM usage_rollup_meta WHERE key = 'hourly_app_backfilled_v1' LIMIT 1",
                parameters: []
            ) { _ in 1 }
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    static func fetchHourlyAppUsageFromRollups(db: OpaquePointer, filters: FilterSnapshot) throws -> [HourlyAppUsage] {
        let range = normalizedDateRange(filters: filters)
        let dayStart = String(range.startISO.prefix(10))
        let dayEndExclusive = String(range.endExclusiveISO.prefix(10))
        let scope = try usageRollupScope(db: db, range: range)

        var conditions = [
            "rollup_scope = ?",
            "day >= ?",
            "day < ?",
            "stream_type IN ('app_usage', 'web_usage', 'media_usage')"
        ]
        var parameters: [SQLiteBinding] = [
            .text(scope),
            .text(dayStart),
            .text(dayEndExclusive)
        ]

        if !filters.selectedApps.isEmpty {
            let sortedApps = filters.selectedApps.sorted()
            conditions.append("app_name IN (\(placeholders(count: sortedApps.count)))")
            parameters.append(contentsOf: sortedApps.map { .text($0) })
        }

        let sql = """
        SELECT hour, app_name, SUM(total_seconds) AS total_seconds
        FROM usage_hourly_app_rollups
        WHERE \(conditions.joined(separator: " AND "))
        GROUP BY hour, app_name
        ORDER BY hour, total_seconds DESC
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            HourlyAppUsage(
                hour: Int(SQLiteRunner.columnInt(statement, index: 0)),
                appName: SQLiteRunner.columnText(statement, index: 1) ?? "Unknown",
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 2)
            )
        }
    }

    static func hasDirectObservations(
        db: OpaquePointer,
        range: (startISO: String, endExclusiveISO: String)
    ) throws -> Bool {
        let sql = """
        SELECT 1
        FROM usage
        WHERE metadata_hash = 'direct_observation'
          AND start_time >= ?
          AND start_time < ?
        LIMIT 1
        """
        let directRows: [Int] = try SQLiteRunner.query(db: db, sql: sql, parameters: [
            .text(range.startISO),
            .text(range.endExclusiveISO)
        ]) { _ in 1 }
        return !directRows.isEmpty
    }

    static func usageRollupScope(
        db: OpaquePointer,
        range: (startISO: String, endExclusiveISO: String)
    ) throws -> String {
        try hasDirectObservations(db: db, range: range) ? "direct" : "all"
    }

    // MARK: - Longest session queries

    static func fetchLongestSessionNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> LongestSession? {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: false, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT u.app_name, u.duration_seconds, u.start_time
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        ORDER BY u.duration_seconds DESC
        LIMIT 1
        """

        let rows: [LongestSession] = try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            let appName = SQLiteRunner.columnText(statement, index: 0) ?? "Unknown"
            let duration = SQLiteRunner.columnDouble(statement, index: 1)
            let startText = SQLiteRunner.columnText(statement, index: 2) ?? ""
            let startDate = parseISO(startText) ?? .distantPast
            return LongestSession(appName: appName, durationSeconds: duration, startDate: startDate)
        }
        return rows.first
    }

    // MARK: - Raw session queries

    static func fetchRawSessionsNormalized(
        db: OpaquePointer,
        filters: FilterSnapshot,
        hasCategoryMap: Bool,
        limit: Int? = nil
    ) throws -> [RawSession] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "
        let limitClause = limit.map { _ in "LIMIT ?" } ?? ""

        let sql = """
        SELECT
            u.app_name,
            u.start_time,
            u.duration_seconds
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        ORDER BY u.start_time ASC
        \(limitClause)
        """

        var parameters = filter.parameters
        if let limit {
            parameters.append(.int(Int64(max(limit, 0))))
        }

        return try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            let appName = SQLiteRunner.columnText(statement, index: 0) ?? "Unknown"
            let startTimeText = SQLiteRunner.columnText(statement, index: 1) ?? ""
            let duration = SQLiteRunner.columnDouble(statement, index: 2)

            let startTime = parseISO(startTimeText) ?? .distantPast
            let endTime = startTime.addingTimeInterval(duration)

            return RawSession(
                appName: appName,
                startTime: startTime,
                endTime: endTime,
                durationSeconds: duration
            )
        }
        .filter { $0.startTime != .distantPast }
    }

    static func fetchRawSessionCountNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> Int {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT COUNT(*) FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        """

        let count = try SQLiteRunner.scalarDouble(db: db, sql: sql, parameters: filter.parameters) ?? 0
        return Int(count)
    }

    // MARK: - Context switch queries

    static func fetchContextSwitchesNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [ContextSwitchPoint] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        // Use LAG window function to detect app switches
        let sql = """
        SELECT day, hour, COUNT(*) AS switch_count
        FROM (
            SELECT
                date(u.start_time) AS day,
                CAST(strftime('%H', u.start_time) AS INTEGER) AS hour,
                u.app_name,
                LAG(u.app_name) OVER (ORDER BY u.start_time) AS prev_app
            FROM usage u
            \(join)
            WHERE \(filter.whereClause)
        ) t
        WHERE prev_app IS NOT NULL AND app_name != prev_app
        GROUP BY day, hour
        ORDER BY day, hour
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            let dayText = SQLiteRunner.columnText(statement, index: 0) ?? ""
            let parsedDay = parseDay(dayText) ?? .distantPast
            return ContextSwitchPoint(
                date: parsedDay,
                hour: Int(SQLiteRunner.columnInt(statement, index: 1)),
                switchCount: Int(SQLiteRunner.columnInt(statement, index: 2))
            )
        }
        .filter { $0.date != .distantPast }
    }

    // MARK: - App transition queries

    static func fetchAppTransitionsNormalized(db: OpaquePointer, filters: FilterSnapshot, limit: Int, hasCategoryMap: Bool) throws -> [AppTransition] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT prev_app, app_name, COUNT(*) AS transition_count
        FROM (
            SELECT
                u.app_name,
                LAG(u.app_name) OVER (ORDER BY u.start_time) AS prev_app
            FROM usage u
            \(join)
            WHERE \(filter.whereClause)
        ) t
        WHERE prev_app IS NOT NULL AND app_name != prev_app
        GROUP BY prev_app, app_name
        ORDER BY transition_count DESC
        LIMIT ?
        """

        var parameters = filter.parameters
        parameters.append(.int(Int64(limit)))

        return try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            AppTransition(
                fromApp: SQLiteRunner.columnText(statement, index: 0) ?? "Unknown",
                toApp: SQLiteRunner.columnText(statement, index: 1) ?? "Unknown",
                count: Int(SQLiteRunner.columnInt(statement, index: 2))
            )
        }
    }

    // MARK: - Weekday average queries

    static func fetchWeekdayAveragesNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [WeekdayAverage] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        // Get top app per weekday along with its total seconds and the count of distinct days
        // This ensures the displayed time matches the displayed app name
        let sql = """
        SELECT weekday, app_name, total_seconds, day_count FROM (
            SELECT
                CAST(strftime('%w', u.start_time) AS INTEGER) AS weekday,
                u.app_name,
                SUM(u.duration_seconds) AS total_seconds,
                COUNT(DISTINCT date(u.start_time)) AS day_count,
                ROW_NUMBER() OVER (PARTITION BY CAST(strftime('%w', u.start_time) AS INTEGER) ORDER BY SUM(u.duration_seconds) DESC) AS rn
            FROM usage u
            \(join)
            WHERE \(filter.whereClause)
            GROUP BY weekday, u.app_name
        ) t
        WHERE rn = 1
        ORDER BY weekday
        """

        return try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            let weekday = Int(SQLiteRunner.columnInt(statement, index: 0))
            let appName = SQLiteRunner.columnText(statement, index: 1) ?? "Unknown"
            let totalSeconds = SQLiteRunner.columnDouble(statement, index: 2)
            let dayCount = Int(SQLiteRunner.columnInt(statement, index: 3))
            
            return WeekdayAverage(
                weekday: weekday,
                averageSeconds: dayCount > 0 ? totalSeconds / Double(dayCount) : 0,
                topApp: appName
            )
        }
    }

    static func parseISO(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }

    static func fetchDailyTotalsNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [DailyTotalRow] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            date(u.start_time) AS day,
            SUM(u.duration_seconds) AS total_seconds
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        GROUP BY day
        ORDER BY day
        """

        return try dailyTotalsFromQuery(db: db, sql: sql, parameters: filter.parameters)
    }

    // MARK: - Daily per-app breakdown queries

    static func fetchDailyAppRowsNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> [DailyAppRow] {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "

        let sql = """
        SELECT
            date(u.start_time) AS day,
            u.app_name,
            SUM(u.duration_seconds) AS total_seconds
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)
        GROUP BY day, u.app_name
        ORDER BY day, total_seconds DESC
        """

        return try dailyAppRowsFromQuery(db: db, sql: sql, parameters: filter.parameters)
    }

    static func dailyAppRowsFromQuery(db: OpaquePointer, sql: String, parameters: [SQLiteBinding]) throws -> [DailyAppRow] {
        try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            let dayText = SQLiteRunner.columnText(statement, index: 0) ?? ""
            let parsedDay = parseDay(dayText) ?? .distantPast
            return DailyAppRow(
                day: parsedDay,
                appName: SQLiteRunner.columnText(statement, index: 1) ?? "Unknown",
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 2)
            )
        }
        .filter { $0.day != .distantPast }
    }

    /// Aggregates raw per-day-per-app rows into `DailyAppBreakdown` with the top N apps
    /// and everything else bucketed as "Other". Fills in zero-usage days for continuity.
    static func aggregateDailyAppBreakdown(rawRows: [DailyAppRow], filters: FilterSnapshot, topN: Int) -> [DailyAppBreakdown] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: filters.startDate)
        let end = calendar.startOfDay(for: filters.endDate)
        guard start <= end else { return [] }

        // Determine the top N apps by total usage across the entire range
        var appTotals: [String: Double] = [:]
        for row in rawRows {
            appTotals[row.appName, default: 0] += row.totalSeconds
        }
        let topAppNames = Set(
            appTotals.sorted { $0.value > $1.value }
                .prefix(topN)
                .map(\.key)
        )

        // Group raw data by day → app (bucketing non-top into "Other")
        var dayAppMap: [Date: [String: Double]] = [:]
        for row in rawRows {
            let name = topAppNames.contains(row.appName) ? row.appName : "Other"
            dayAppMap[row.day, default: [:]][name, default: 0] += row.totalSeconds
        }

        // All app names that will appear (sorted for consistent stacking order)
        let allNames = topAppNames.sorted() + (dayAppMap.values.contains { $0.keys.contains("Other") } ? ["Other"] : [])

        // Walk every day and emit a point per app (including zero days)
        var result: [DailyAppBreakdown] = []
        var cursor = start
        while cursor <= end {
            let dayData = dayAppMap[cursor] ?? [:]
            for name in allNames {
                result.append(DailyAppBreakdown(
                    date: cursor,
                    appName: name,
                    totalSeconds: dayData[name] ?? 0
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    static func totalUsageSecondsNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> Double {
        try fetchUsageStatsNormalized(db: db, filters: filters, hasCategoryMap: hasCategoryMap).totalSeconds
    }

    static func fetchDistinctAppCountNormalized(db: OpaquePointer, filters: FilterSnapshot, hasCategoryMap: Bool) throws -> Int {
        try fetchUsageStatsNormalized(db: db, filters: filters, hasCategoryMap: hasCategoryMap).uniqueAppCount
    }

    static func fetchUsageStatsNormalized(
        db: OpaquePointer,
        filters: FilterSnapshot,
        hasCategoryMap: Bool,
        includeWebUsage: Bool = true
    ) throws -> UsageStats {
        let filter = try normalizedFilter(filters: filters, alias: "u", hasCategoryMap: hasCategoryMap, includeCategorySelection: true, db: db)
        let join = filter.needsCategoryJoin ? " LEFT JOIN app_category_map m ON m.app_name = u.app_name " : " "
        let webUsagePredicate = includeWebUsage ? "" : " AND u.stream_type != 'web_usage'"

        let sql = """
        SELECT
            COALESCE(SUM(u.duration_seconds), 0) AS total_seconds,
            COUNT(*) AS session_count,
            COUNT(DISTINCT u.app_name) AS unique_app_count
        FROM usage u
        \(join)
        WHERE \(filter.whereClause)\(webUsagePredicate)
        """

        let rows: [UsageStats] = try SQLiteRunner.query(db: db, sql: sql, parameters: filter.parameters) { statement in
            UsageStats(
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 0),
                sessionCount: Int(SQLiteRunner.columnInt(statement, index: 1)),
                uniqueAppCount: Int(SQLiteRunner.columnInt(statement, index: 2))
            )
        }
        return rows.first ?? UsageStats(totalSeconds: 0, sessionCount: 0, uniqueAppCount: 0)
    }

    static func focusRowsFromQuery(db: OpaquePointer, sql: String, parameters: [SQLiteBinding]) throws -> [FocusDayRow] {
        try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            let dayText = SQLiteRunner.columnText(statement, index: 0) ?? ""
            let parsedDay = parseDay(dayText) ?? .distantPast
            return FocusDayRow(
                day: parsedDay,
                totalSeconds: SQLiteRunner.columnDouble(statement, index: 1),
                focusBlocks: Int(SQLiteRunner.columnInt(statement, index: 2))
            )
        }
        .filter { $0.day != .distantPast }
    }

    static func dailyTotalsFromQuery(db: OpaquePointer, sql: String, parameters: [SQLiteBinding]) throws -> [DailyTotalRow] {
        try SQLiteRunner.query(db: db, sql: sql, parameters: parameters) { statement in
            let dayText = SQLiteRunner.columnText(statement, index: 0) ?? ""
            let parsedDay = parseDay(dayText) ?? .distantPast
            return DailyTotalRow(day: parsedDay, totalSeconds: SQLiteRunner.columnDouble(statement, index: 1))
        }
        .filter { $0.day != .distantPast }
    }
}

// MARK: - Filters / aggregation

private extension SQLiteScreenTimeDataService {
    static func previousPeriodFilters(for filters: FilterSnapshot, calendar: Calendar = .current) -> FilterSnapshot {
        let previousStart: Date
        switch filters.granularity {
        case .day:
            previousStart = calendar.date(byAdding: .day, value: -1, to: filters.startDate) ?? filters.startDate
        case .week:
            previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: filters.startDate) ?? filters.startDate
        case .month:
            previousStart = calendar.date(byAdding: .month, value: -1, to: filters.startDate) ?? filters.startDate
        case .year:
            previousStart = calendar.date(byAdding: .year, value: -1, to: filters.startDate) ?? filters.startDate
        }

        return replacingRange(in: filters, start: previousStart, end: filters.startDate)
    }

    static func previousComparisonFilters(for filters: FilterSnapshot, calendar: Calendar = .current) -> FilterSnapshot? {
        let rangeDays = calendar.dateComponents([.day], from: filters.startDate, to: filters.endDate).day ?? 7
        guard let previousEnd = calendar.date(byAdding: .day, value: -1, to: filters.startDate),
              let previousStart = calendar.date(byAdding: .day, value: -rangeDays, to: previousEnd) else {
            return nil
        }
        return replacingRange(in: filters, start: previousStart, end: previousEnd)
    }

    static func replacingRange(in filters: FilterSnapshot, start startDate: Date, end endDate: Date) -> FilterSnapshot {
        FilterSnapshot(
            startDate: startDate,
            endDate: endDate,
            granularity: filters.granularity,
            selectedApps: filters.selectedApps,
            selectedCategories: filters.selectedCategories,
            selectedHeatmapCells: filters.selectedHeatmapCells,
            timeOfDayRanges: filters.timeOfDayRanges,
            weekdayFilter: filters.weekdayFilter,
            minDurationSeconds: filters.minDurationSeconds,
            maxDurationSeconds: filters.maxDurationSeconds
        )
    }

    static func restricting(_ filters: FilterSnapshot, toApp selectedApp: String?) -> FilterSnapshot {
        guard let selectedApp else { return filters }
        return FilterSnapshot(
            startDate: filters.startDate,
            endDate: filters.endDate,
            granularity: filters.granularity,
            selectedApps: [selectedApp],
            selectedCategories: filters.selectedCategories,
            selectedHeatmapCells: filters.selectedHeatmapCells,
            timeOfDayRanges: filters.timeOfDayRanges,
            weekdayFilter: filters.weekdayFilter,
            minDurationSeconds: filters.minDurationSeconds,
            maxDurationSeconds: filters.maxDurationSeconds
        )
    }

    static func buildPeriodDelta(
        currentApps: [AppUsageSummary],
        previousApps: [AppUsageSummary],
        currentTotal: Double,
        previousTotal: Double,
        currentAppsUsed: Int,
        previousAppsUsed: Int
    ) -> PeriodDelta {
        let percentChange: Double = previousTotal > 0
            ? ((currentTotal - previousTotal) / previousTotal) * 100
            : (currentTotal > 0 ? 100 : 0)

        let currentMap = Dictionary(uniqueKeysWithValues: currentApps.map { ($0.appName, $0.totalSeconds) })
        let previousMap = Dictionary(uniqueKeysWithValues: previousApps.map { ($0.appName, $0.totalSeconds) })
        let allApps = Set(currentMap.keys).union(previousMap.keys)

        var deltas: [AppDelta] = []
        deltas.reserveCapacity(allApps.count)
        for app in allApps {
            deltas.append(AppDelta(
                appName: app,
                currentSeconds: currentMap[app] ?? 0,
                previousSeconds: previousMap[app] ?? 0
            ))
        }
        deltas.sort { abs($0.currentSeconds - $0.previousSeconds) > abs($1.currentSeconds - $1.previousSeconds) }

        return PeriodDelta(
            currentTotalSeconds: currentTotal,
            previousTotalSeconds: previousTotal,
            percentChange: percentChange,
            currentAppsUsed: currentAppsUsed,
            previousAppsUsed: previousAppsUsed,
            appDeltas: Array(deltas.prefix(20))
        )
    }

    static func buildPeriodSummary(
        db: OpaquePointer,
        filters: FilterSnapshot,
        hasCategoryMap: Bool,
        currentApps: [AppUsageSummary]? = nil
    ) throws -> PeriodSummary {
        let apps = try currentApps ?? fetchTopAppsNormalized(
            db: db,
            filters: filters,
            limit: 200,
            hasCategoryMap: hasCategoryMap
        )
        let currentStats = try fetchUsageStatsNormalized(
            db: db,
            filters: filters,
            hasCategoryMap: hasCategoryMap,
            includeWebUsage: false
        )
        let previousFilters = previousPeriodFilters(for: filters)
        let previousStats = try fetchUsageStatsNormalized(
            db: db,
            filters: previousFilters,
            hasCategoryMap: hasCategoryMap,
            includeWebUsage: false
        )
        let heatmap = try fetchHeatmapNormalized(db: db, filters: filters, hasCategoryMap: hasCategoryMap)
        let hourTotals = Dictionary(grouping: heatmap, by: { $0.hour })
            .mapValues { cells in cells.reduce(0.0) { $0 + $1.totalSeconds } }
        let peak = hourTotals.max(by: { $0.value < $1.value })
        let topApp = apps.first

        return PeriodSummary(
            granularity: filters.granularity,
            totalSeconds: currentStats.totalSeconds,
            previousTotalSeconds: previousStats.totalSeconds,
            peakHour: peak?.key ?? 0,
            peakHourSeconds: peak?.value ?? 0,
            appsUsedCount: currentStats.uniqueAppCount,
            topAppName: topApp?.appName ?? "None",
            topAppSeconds: topApp?.totalSeconds ?? 0
        )
    }

    static func fetchPeriodDeltaNormalized(
        db: OpaquePointer,
        current: FilterSnapshot,
        hasCategoryMap: Bool,
        currentApps: [AppUsageSummary]? = nil,
        currentStats: UsageStats? = nil
    ) throws -> PeriodDelta? {
        guard let previous = previousComparisonFilters(for: current) else { return nil }
        let resolvedCurrentApps = try currentApps ?? fetchTopAppsNormalized(
            db: db,
            filters: current,
            limit: 200,
            hasCategoryMap: hasCategoryMap
        )
        let resolvedCurrentStats = try currentStats ?? fetchUsageStatsNormalized(
            db: db,
            filters: current,
            hasCategoryMap: hasCategoryMap,
            includeWebUsage: false
        )
        let previousApps = try fetchTopAppsNormalized(
            db: db,
            filters: previous,
            limit: 200,
            hasCategoryMap: hasCategoryMap
        )
        let previousStats = try fetchUsageStatsNormalized(
            db: db,
            filters: previous,
            hasCategoryMap: hasCategoryMap,
            includeWebUsage: false
        )

        return buildPeriodDelta(
            currentApps: resolvedCurrentApps,
            previousApps: previousApps,
            currentTotal: resolvedCurrentStats.totalSeconds,
            previousTotal: previousStats.totalSeconds,
            currentAppsUsed: resolvedCurrentStats.uniqueAppCount,
            previousAppsUsed: previousStats.uniqueAppCount
        )
    }

    static func completeFocusDays(rows: [FocusDayRow], filters: FilterSnapshot) -> [FocusDay] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: filters.startDate)
        let end = calendar.startOfDay(for: filters.endDate)
        let mapped = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })

        var result: [FocusDay] = []
        var cursor = start
        while cursor <= end {
            if let row = mapped[cursor] {
                result.append(FocusDay(date: cursor, focusBlocks: row.focusBlocks, totalSeconds: row.totalSeconds))
            } else {
                result.append(FocusDay(date: cursor, focusBlocks: 0, totalSeconds: 0))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    static func dashboardSummary(from focusDays: [FocusDay]) -> DashboardSummary {
        let totalSeconds = focusDays.reduce(0) { $0 + $1.totalSeconds }
        let averageDailySeconds = focusDays.isEmpty ? 0 : totalSeconds / Double(focusDays.count)
        let focusBlocks = focusDays.reduce(0) { $0 + $1.focusBlocks }
        return DashboardSummary(
            totalSeconds: totalSeconds,
            averageDailySeconds: averageDailySeconds,
            focusBlocks: focusBlocks
        )
    }

    static func completeHeatmap(cells: [HeatmapCell]) -> [HeatmapCell] {
        var byCoordinate = Dictionary(uniqueKeysWithValues: cells.map { (HeatmapCellCoordinate(weekday: $0.weekday, hour: $0.hour), $0.totalSeconds) })
        var completed: [HeatmapCell] = []
        completed.reserveCapacity(7 * 24)
        for weekday in 0..<7 {
            for hour in 0..<24 {
                let coordinate = HeatmapCellCoordinate(weekday: weekday, hour: hour)
                completed.append(HeatmapCell(
                    weekday: weekday,
                    hour: hour,
                    totalSeconds: byCoordinate.removeValue(forKey: coordinate) ?? 0
                ))
            }
        }
        return completed
    }

    static func hourlySparklinePointsIfNeeded(
        db: OpaquePointer,
        filters: FilterSnapshot,
        hasCategoryMap: Bool
    ) throws -> [SparklinePoint] {
        guard filters.granularity == .day else { return [] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: filters.startDate)
        let dayFilters = FilterSnapshot(
            startDate: dayStart,
            endDate: dayStart,
            granularity: .day,
            selectedApps: filters.selectedApps,
            selectedCategories: filters.selectedCategories,
            selectedHeatmapCells: filters.selectedHeatmapCells,
            timeOfDayRanges: filters.timeOfDayRanges,
            weekdayFilter: filters.weekdayFilter,
            minDurationSeconds: filters.minDurationSeconds,
            maxDurationSeconds: filters.maxDurationSeconds
        )
        let hourlyData = try fetchHourlyAppUsageNormalized(db: db, filters: dayFilters, hasCategoryMap: hasCategoryMap)
        let hourlyTotals = Dictionary(grouping: hourlyData, by: { $0.hour })
            .mapValues { rows in rows.reduce(0.0) { $0 + $1.totalSeconds } }
        return (0..<24).compactMap { hour in
            guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) else { return nil }
            return SparklinePoint(date: hourDate, totalSeconds: hourlyTotals[hour, default: 0])
        }
    }

    static func buildInsights(
        summary: DashboardSummary,
        topApps: [AppUsageSummary],
        buckets: [SessionBucket],
        longest: LongestSession?,
        weekdayAvgs: [WeekdayAverage]
    ) -> [Insight] {
        var insights: [Insight] = []

        let totalHours = summary.totalSeconds / 3600
        insights.append(Insight(
            icon: "clock.fill",
            text: String(format: "Total screen time: %.1fh across the selected period", totalHours),
            sentiment: .neutral
        ))

        let avgHours = summary.averageDailySeconds / 3600
        let sentiment: InsightSentiment = avgHours < 4 ? .positive : avgHours > 6 ? .negative : .neutral
        insights.append(Insight(
            icon: "chart.line.downtrend.xyaxis",
            text: String(format: "Your daily average is %.1fh", avgHours),
            sentiment: sentiment
        ))

        if let top = topApps.first {
            let pct = summary.totalSeconds > 0 ? (top.totalSeconds / summary.totalSeconds) * 100 : 0
            insights.append(Insight(
                icon: "star.fill",
                text: String(format: "%@ accounts for %.0f%% of your screen time", top.appName, pct),
                sentiment: .neutral
            ))
        }

        insights.append(Insight(
            icon: "square.grid.3x3.fill",
            text: "You used \(topApps.count > 4 ? "5+" : "\(topApps.count)") different apps",
            sentiment: .neutral
        ))

        if let longest {
            insights.append(Insight(
                icon: "timer",
                text: String(format: "Longest session: %@ in %@", DurationFormatter.short(longest.durationSeconds), longest.appName),
                sentiment: longest.durationSeconds > 7200 ? .negative : .neutral
            ))
        }

        if let peakBucket = buckets.max(by: { $0.sessionCount < $1.sessionCount }) {
            insights.append(Insight(
                icon: "chart.bar.fill",
                text: "Most sessions are \(peakBucket.label) long (\(peakBucket.sessionCount) sessions)",
                sentiment: .neutral
            ))
        }

        if let busiest = weekdayAvgs.max(by: { $0.averageSeconds < $1.averageSeconds }) {
            let dayNames = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
            let dayName = busiest.weekday < dayNames.count ? dayNames[busiest.weekday] : "Day \(busiest.weekday)"
            insights.append(Insight(
                icon: "calendar",
                text: String(format: "%@ are your busiest — %.1fh avg, mostly %@", dayName, busiest.averageSeconds / 3600, busiest.topApp),
                sentiment: .neutral
            ))
        }

        if let quietest = weekdayAvgs.min(by: { $0.averageSeconds < $1.averageSeconds }),
           weekdayAvgs.count > 1 {
            let dayNames = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
            let dayName = quietest.weekday < dayNames.count ? dayNames[quietest.weekday] : "Day \(quietest.weekday)"
            insights.append(Insight(
                icon: "moon.fill",
                text: String(format: "%@ are your lightest — %.1fh avg", dayName, quietest.averageSeconds / 3600),
                sentiment: .positive
            ))
        }

        return insights
    }

    static func normalizedFilter(
        filters: FilterSnapshot,
        alias: String,
        hasCategoryMap: Bool,
        includeCategorySelection: Bool,
        db: OpaquePointer
    ) throws -> SQLFilter {
        let range = normalizedDateRange(filters: filters)

        var conditions: [String] = [
            "\(alias).stream_type IN ('app_usage', 'web_usage', 'media_usage')",
            "\(alias).start_time >= ?",
            "\(alias).start_time < ?"
        ]

        var parameters: [SQLiteBinding] = [
            .text(range.startISO),
            .text(range.endExclusiveISO)
        ]

        // Prefer direct_observation over knowledgeC to avoid double-counting.
        // The old filter used a NOT EXISTS subquery inside every analytics query;
        // compute the range-wide source scope once instead so SQLite can use simple
        // date/stream indexes for the main query.
        if try hasDirectObservations(db: db, range: range) {
            conditions.append("\(alias).metadata_hash = 'direct_observation'")
        }

        if !filters.selectedApps.isEmpty {
            let sortedApps = filters.selectedApps.sorted()
            conditions.append("\(alias).app_name IN (\(placeholders(count: sortedApps.count)))")
            parameters.append(contentsOf: sortedApps.map { .text($0) })
        }

        if !filters.selectedHeatmapCells.isEmpty {
            let sortedCells = filters.selectedHeatmapCells.sorted { lhs, rhs in
                if lhs.weekday == rhs.weekday {
                    return lhs.hour < rhs.hour
                }
                return lhs.weekday < rhs.weekday
            }

            let cellPredicates = sortedCells.map { _ in
                "(CAST(strftime('%w', \(alias).start_time) AS INTEGER) = ? AND CAST(strftime('%H', \(alias).start_time) AS INTEGER) = ?)"
            }
            conditions.append("(\(cellPredicates.joined(separator: " OR ")))")

            for cell in sortedCells {
                parameters.append(.int(Int64(cell.weekday)))
                parameters.append(.int(Int64(cell.hour)))
            }
        }

        var needsCategoryJoin = false
        if includeCategorySelection, !filters.selectedCategories.isEmpty {
            if hasCategoryMap {
                let sortedCategories = filters.selectedCategories.sorted()
                conditions.append("COALESCE(m.category, 'Uncategorized') IN (\(placeholders(count: sortedCategories.count)))")
                parameters.append(contentsOf: sortedCategories.map { .text($0) })
                needsCategoryJoin = true
            } else if !filters.selectedCategories.contains("Uncategorized") {
                conditions.append("1 = 0")
            }
        }
        
        // ── Advanced Time Filters ──
        
        // Time-of-day ranges (OR logic)
        if !filters.timeOfDayRanges.isEmpty {
            let hourExpr = "CAST(strftime('%H', \(alias).start_time) AS INTEGER)"
            var rangePredicates: [String] = []
            
            for range in filters.timeOfDayRanges {
                if range.startHour <= range.endHour {
                    // Normal range (e.g., 9-17)
                    rangePredicates.append("(\(hourExpr) >= ? AND \(hourExpr) < ?)")
                    parameters.append(.int(Int64(range.startHour)))
                    parameters.append(.int(Int64(range.endHour)))
                } else {
                    // Overnight range (e.g., 22-6)
                    rangePredicates.append("(\(hourExpr) >= ? OR \(hourExpr) < ?)")
                    parameters.append(.int(Int64(range.startHour)))
                    parameters.append(.int(Int64(range.endHour)))
                }
            }
            
            conditions.append("(\(rangePredicates.joined(separator: " OR ")))")
        }
        
        // Weekday filter (OR logic)
        if !filters.weekdayFilter.isEmpty {
            let weekdayExpr = "CAST(strftime('%w', \(alias).start_time) AS INTEGER)"
            let sortedWeekdays = filters.weekdayFilter.sorted()
            conditions.append("\(weekdayExpr) IN (\(placeholders(count: sortedWeekdays.count)))")
            parameters.append(contentsOf: sortedWeekdays.map { .int(Int64($0)) })
        }
        
        // Duration thresholds
        if let minDuration = filters.minDurationSeconds {
            conditions.append("\(alias).duration_seconds >= ?")
            parameters.append(.double(minDuration))
        }
        
        if let maxDuration = filters.maxDurationSeconds {
            conditions.append("\(alias).duration_seconds <= ?")
            parameters.append(.double(maxDuration))
        }

        return SQLFilter(whereClause: conditions.joined(separator: " AND "), parameters: parameters, needsCategoryJoin: needsCategoryJoin)
    }

    static func aggregateTrend(dailyTotals: [DailyTotalRow], filters: FilterSnapshot) -> [TrendPoint] {
        let calendar = Calendar.current

        var dayMap: [Date: Double] = [:]
        for row in dailyTotals {
            dayMap[row.day] = row.totalSeconds
        }

        let start = calendar.startOfDay(for: filters.startDate)
        let end = calendar.startOfDay(for: filters.endDate)

        guard start <= end else { return [] }

        switch filters.granularity {
        case .day, .year, .week, .month:
            // Always show daily breakdown so the chart has meaningful bars
            // regardless of whether the range spans a single week or month.
            var points: [TrendPoint] = []
            var cursor = start
            while cursor <= end {
                points.append(TrendPoint(date: cursor, totalSeconds: dayMap[cursor] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                    break
                }
                cursor = next
            }
            return points
        }
    }

    static func normalizedDateRange(filters: FilterSnapshot) -> (startISO: String, endExclusiveISO: String) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: filters.startDate)
        let endStart = calendar.startOfDay(for: filters.endDate)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endStart) ?? endStart

        return (
            isoDateTime(start),
            isoDateTime(endExclusive)
        )
    }



    static func parseDay(_ value: String) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0

        return Calendar.current.date(from: components)
    }

    static func isoDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }

    static func placeholders(count: Int) -> String {
        guard count > 0 else { return "" }
        return Array(repeating: "?", count: count).joined(separator: ",")
    }
}

// MARK: - Database resolution / validation

private extension SQLiteScreenTimeDataService {
    nonisolated static func openConnectionContext(
        pathOverride: String?,
        installCategoryMappings: Bool
    ) throws -> SQLiteConnectionContext {
        let resolved = try resolveDatabase(pathOverride: pathOverride)
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(resolved.url.path, &dbPointer, flags, nil)

        guard openResult == SQLITE_OK, let db = dbPointer else {
            let message = dbPointer.flatMap { sqliteMessage(db: $0) } ?? "Unable to open database"
            if let dbPointer {
                sqlite3_close(dbPointer)
            }
            if openResult == SQLITE_CANTOPEN || openResult == SQLITE_PERM || openResult == SQLITE_AUTH {
                throw ScreenTimeDataError.permissionDenied(path: resolved.url.path)
            }
            throw ScreenTimeDataError.sqlite(path: resolved.url.path, message: message)
        }

        do {
            sqlite3_busy_timeout(db, 5000)

            try validateNormalizedSchema(db: db, path: resolved.url.path)

            if installCategoryMappings {
                do {
                    try CategoryMappingStore.installMappingsIntoTemporaryTable(into: db, path: resolved.url.path)
                } catch {
                    throw ScreenTimeDataError.sqlite(
                        path: resolved.url.path,
                        message: "Failed to install temporary category mappings. Underlying error: \(ScreenTimeDataError.message(for: error))"
                    )
                }
            }

            return SQLiteConnectionContext(
                sourceURL: resolved.url,
                hasCategoryMap: installCategoryMappings,
                db: db
            )
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    nonisolated static func resolveDatabase(pathOverride: String?) throws -> ResolvedDatabase {
        if let pathOverride {
            let expanded = (pathOverride as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ScreenTimeDataError.databaseNotFound(searchedPaths: ["SCREENTIME_DB_PATH=\(url.path)"])
            }

            guard try detectNormalizedBackend(url: url) else {
                throw ScreenTimeDataError.schemaMismatch(
                    path: url.path,
                    details: "Expected a normalized 'usage' table. If this is a raw export, ensure the full SQLite file was copied (including current schema)."
                )
            }

            return ResolvedDatabase(url: url)
        }

        let sandboxHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let userHome = realHomeDirectory()
        let canonicalDatabaseURL = userHome.appendingPathComponent("Library/Application Support/time.md/screentime.db")
        var candidates = [
            canonicalDatabaseURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent("screentime.db"),
            URL(fileURLWithPath: "/data/screentime.db"),
            sandboxHome.appendingPathComponent("screentime.db"),
        ]
        let sandboxAppSupport = sandboxHome.appendingPathComponent("Library/Application Support/time.md/screentime.db")
        if sandboxAppSupport.path != candidates[0].path {
            candidates.append(sandboxAppSupport)
        }

        var searched: [String] = []

        for candidate in candidates {
            searched.append(candidate.path)
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                continue
            }

            if try detectNormalizedBackend(url: candidate) {
                if candidate.standardizedFileURL.path == canonicalDatabaseURL.standardizedFileURL.path {
                    // Ensure newly added performance indexes are present before
                    // the first read-only dashboard query races ahead of the
                    // writer/auto-save services on app launch.
                    _ = try HistoryStore.databaseURL()
                }
                return ResolvedDatabase(url: candidate)
            }
        }

        // First-launch race guard: dashboard views can query before the tracker
        // writes its first session, which used to surface a transient "database
        // not found" banner until the user navigated away and back. If discovery
        // finds no existing normalized database, create the canonical empty store
        // and let the query return zero rows instead of an error.
        do {
            return ResolvedDatabase(url: try HistoryStore.databaseURL())
        } catch let dataError as ScreenTimeDataError {
            throw dataError
        } catch {
            throw ScreenTimeDataError.sqlite(path: candidates[0].path, message: error.localizedDescription)
        }
    }

    nonisolated static func detectNormalizedBackend(url: URL) throws -> Bool {
        var dbPointer: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &dbPointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)

        guard result == SQLITE_OK, let db = dbPointer else {
            let message = dbPointer.flatMap { sqliteMessage(db: $0) } ?? "Unable to open database"
            if result == SQLITE_CANTOPEN || result == SQLITE_PERM || result == SQLITE_AUTH {
                throw ScreenTimeDataError.permissionDenied(path: url.path)
            }
            throw ScreenTimeDataError.sqlite(path: url.path, message: message)
        }

        defer { sqlite3_close(db) }

        return tableExists(db: db, table: "usage")
    }

    nonisolated static func validateNormalizedSchema(db: OpaquePointer, path: String) throws {
        let columns = try tableColumns(db: db, table: "usage")
        // Core columns are required; device_id and metadata_hash are optional
        // (added by migration, older DBs may not have them yet).
        let required: Set<String> = ["app_name", "duration_seconds", "start_time", "stream_type"]
        let missing = required.subtracting(columns)
        guard missing.isEmpty else {
            let available = columns.sorted().joined(separator: ", ")
            throw ScreenTimeDataError.schemaMismatch(
                path: path,
                details: "Missing usage columns: \(missing.sorted().joined(separator: ", ")). Available columns: [\(available)]."
            )
        }
    }

    nonisolated static func tableExists(db: OpaquePointer, table: String) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        do {
            let rows: [Int] = try SQLiteRunner.query(db: db, sql: sql, parameters: [.text(table)]) { _ in 1 }
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    nonisolated static func tableColumns(db: OpaquePointer, table: String) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table))"
        let names: [String] = try SQLiteRunner.query(db: db, sql: sql, parameters: []) { statement in
            SQLiteRunner.columnText(statement, index: 1) ?? ""
        }
        return Set(names.filter { !$0.isEmpty })
    }

    nonisolated static func sqliteMessage(db: OpaquePointer) -> String {
        guard let cString = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: cString)
    }
}

// MARK: - SQLite helpers

private enum SQLiteBinding: Sendable {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}

nonisolated private enum SQLiteRunner {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func query<T>(
        db: OpaquePointer,
        sql: String,
        parameters: [SQLiteBinding],
        map: (OpaquePointer) throws -> T
    ) throws -> [T] {
        var statementPointer: OpaquePointer?

        let prepare = sqlite3_prepare_v2(db, sql, -1, &statementPointer, nil)
        guard prepare == SQLITE_OK, let statement = statementPointer else {
            throw ScreenTimeDataError.sqlite(path: sqlitePath(db: db), message: String(cString: sqlite3_errmsg(db)))
        }

        defer { sqlite3_finalize(statement) }

        try bind(parameters, to: statement, db: db)

        var results: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                results.append(try map(statement))
                continue
            }

            if step == SQLITE_DONE {
                break
            }

            throw ScreenTimeDataError.sqlite(path: sqlitePath(db: db), message: String(cString: sqlite3_errmsg(db)))
        }

        return results
    }

    static func scalarDouble(db: OpaquePointer, sql: String, parameters: [SQLiteBinding]) throws -> Double? {
        let rows: [Double?] = try query(db: db, sql: sql, parameters: parameters) { statement in
            if sqlite3_column_type(statement, 0) == SQLITE_NULL {
                return nil
            }
            return sqlite3_column_double(statement, 0)
        }
        return rows.first ?? nil
    }

    static func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: cString)
    }

    static func columnInt(_ statement: OpaquePointer, index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    static func columnDouble(_ statement: OpaquePointer, index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private static func bind(_ parameters: [SQLiteBinding], to statement: OpaquePointer, db: OpaquePointer) throws {
        for (index, parameter) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)
            let result: Int32

            switch parameter {
            case let .text(value):
                result = sqlite3_bind_text(statement, bindIndex, value, -1, sqliteTransient)
            case let .int(value):
                result = sqlite3_bind_int64(statement, bindIndex, value)
            case let .double(value):
                result = sqlite3_bind_double(statement, bindIndex, value)
            case .null:
                result = sqlite3_bind_null(statement, bindIndex)
            }

            guard result == SQLITE_OK else {
                throw ScreenTimeDataError.sqlite(path: sqlitePath(db: db), message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private static func sqlitePath(db: OpaquePointer) -> String {
        guard let cPath = sqlite3_db_filename(db, "main") else {
            return "<unknown sqlite database>"
        }

        let path = String(cString: cPath)
        return path.isEmpty ? "<unknown sqlite database>" : path
    }
}

// MARK: - Local support types

private struct ResolvedDatabase {
    let url: URL
}

private struct SQLFilter {
    let whereClause: String
    let parameters: [SQLiteBinding]
    let needsCategoryJoin: Bool
}

private struct DailyTotalRow {
    let day: Date
    let totalSeconds: Double
}

private struct DailyAppRow {
    let day: Date
    let appName: String
    let totalSeconds: Double
}

private struct FocusDayRow {
    let day: Date
    let totalSeconds: Double
    let focusBlocks: Int
}

private struct UsageStats {
    let totalSeconds: Double
    let sessionCount: Int
    let uniqueAppCount: Int
}

nonisolated private final class SQLiteConnectionContext {
    let sourceURL: URL
    let hasCategoryMap: Bool
    let db: OpaquePointer

    init(sourceURL: URL, hasCategoryMap: Bool, db: OpaquePointer) {
        self.sourceURL = sourceURL
        self.hasCategoryMap = hasCategoryMap
        self.db = db
    }

    func close() {
        sqlite3_close(db)
    }
}
