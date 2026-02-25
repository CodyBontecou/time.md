import XCTest
@testable import time_md

final class ExportCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCSVExportIncludesExpectedSectionsAndRows() async throws {
        let coordinator = ExportCoordinator(
            dataService: MockDataService.sample,
            outputDirectoryOverride: tempDirectory
        )

        let url = try await coordinator.export(
            format: .csv,
            from: .appsCategories,
            filters: makeFilters()
        )

        XCTAssertEqual(url.pathExtension, "csv")

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("# time.md Export"))
        XCTAssertTrue(content.contains("[Apps]"))
        XCTAssertTrue(content.contains("\"app_name\",\"total_seconds\",\"session_count\""))
        XCTAssertTrue(content.contains("\"YouTube\",\"2400.000\",\"2\""))
        XCTAssertTrue(content.contains("[Categories]"))
        XCTAssertTrue(content.contains("\"Entertainment\",\"2400.000\""))
    }

    func testPNGExportWritesPNGArtifact() async throws {
        let coordinator = ExportCoordinator(
            dataService: MockDataService.sample,
            outputDirectoryOverride: tempDirectory
        )

        let url = try await coordinator.export(
            format: .png,
            from: .overview,
            filters: makeFilters()
        )

        XCTAssertEqual(url.pathExtension, "png")
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 32)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testPDFExportWritesPDFArtifact() async throws {
        let coordinator = ExportCoordinator(
            dataService: MockDataService.sample,
            outputDirectoryOverride: tempDirectory
        )

        let url = try await coordinator.export(
            format: .pdf,
            from: .trends,
            filters: makeFilters()
        )

        XCTAssertEqual(url.pathExtension, "pdf")
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 32)

        let header = String(decoding: data.prefix(5), as: UTF8.self)
        XCTAssertEqual(header, "%PDF-")
    }

    func testUnsupportedDestinationThrowsExportError() async throws {
        let coordinator = ExportCoordinator(
            dataService: MockDataService.sample,
            outputDirectoryOverride: tempDirectory
        )

        do {
            _ = try await coordinator.export(format: .csv, from: .settings, filters: makeFilters())
            XCTFail("Expected unsupportedDestination")
        } catch let error as ExportError {
            guard case .unsupportedDestination = error else {
                XCTFail("Expected unsupportedDestination, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private extension ExportCoordinatorTests {
    func makeFilters() -> FilterSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7)) ?? Date()

        return FilterSnapshot(
            startDate: start,
            endDate: end,
            granularity: .day,
            selectedApps: ["YouTube"],
            selectedCategories: ["Entertainment"],
            selectedHeatmapCells: [HeatmapCellCoordinate(weekday: 1, hour: 9)]
        )
    }
}

private struct MockDataService: ScreenTimeDataServing, @unchecked Sendable {
    static let sample = MockDataService(
        summary: DashboardSummary(totalSeconds: 3_600, averageDailySeconds: 900, focusBlocks: 2),
        trend: [
            TrendPoint(date: Date(timeIntervalSince1970: 1_735_776_000), totalSeconds: 1200),
            TrendPoint(date: Date(timeIntervalSince1970: 1_735_862_400), totalSeconds: 2400)
        ],
        apps: [
            AppUsageSummary(appName: "YouTube", totalSeconds: 2400, sessionCount: 2),
            AppUsageSummary(appName: "Safari", totalSeconds: 1200, sessionCount: 1)
        ],
        categories: [
            CategoryUsageSummary(category: "Entertainment", totalSeconds: 2400),
            CategoryUsageSummary(category: "Uncategorized", totalSeconds: 1200)
        ],
        sessions: [
            SessionBucket(label: "15–30m", sessionCount: 2),
            SessionBucket(label: "5–15m", sessionCount: 1)
        ],
        heatmap: [
            HeatmapCell(weekday: 1, hour: 9, totalSeconds: 2400),
            HeatmapCell(weekday: 2, hour: 10, totalSeconds: 1200)
        ],
        focusDays: [
            FocusDay(date: Date(timeIntervalSince1970: 1_735_776_000), focusBlocks: 1, totalSeconds: 1800),
            FocusDay(date: Date(timeIntervalSince1970: 1_735_862_400), focusBlocks: 1, totalSeconds: 1800)
        ]
    )

    let summary: DashboardSummary
    let trend: [TrendPoint]
    let apps: [AppUsageSummary]
    let categories: [CategoryUsageSummary]
    let sessions: [SessionBucket]
    let heatmap: [HeatmapCell]
    let focusDays: [FocusDay]

    func fetchDashboardSummary(filters: FilterSnapshot) async throws -> DashboardSummary { summary }
    func fetchTrend(filters: FilterSnapshot) async throws -> [TrendPoint] { trend }
    func fetchTopApps(filters: FilterSnapshot, limit: Int) async throws -> [AppUsageSummary] { Array(apps.prefix(max(0, limit))) }
    func fetchTopCategories(filters: FilterSnapshot, limit: Int) async throws -> [CategoryUsageSummary] { Array(categories.prefix(max(0, limit))) }
    func fetchSessionBuckets(filters: FilterSnapshot) async throws -> [SessionBucket] { sessions }
    func fetchHeatmap(filters: FilterSnapshot) async throws -> [HeatmapCell] { heatmap }
    func fetchHeatmapCellAppUsage(filters: FilterSnapshot) async throws -> [HeatmapCellAppUsage] { [] }
    func fetchFocusDays(filters: FilterSnapshot) async throws -> [FocusDay] { focusDays }
    func fetchCategoryMappings() async throws -> [AppCategoryMapping] { [] }
    func saveCategoryMapping(appName: String, category: String) async throws {}
    func deleteCategoryMapping(appName: String) async throws {}

    // Phase 2 — enriched overview
    func fetchTodaySummary() async throws -> TodaySummary {
        TodaySummary(todayTotalSeconds: 3600, yesterdayTotalSeconds: 3000, peakHour: 14, peakHourSeconds: 600, appsUsedCount: 5, topAppName: "YouTube", topAppSeconds: 1200)
    }
    func fetchPeriodSummary(filters: FilterSnapshot) async throws -> PeriodSummary {
        PeriodSummary(granularity: filters.granularity, totalSeconds: 3600, previousTotalSeconds: 3000, peakHour: 14, peakHourSeconds: 600, appsUsedCount: 5, topAppName: "YouTube", topAppSeconds: 1200)
    }
    func fetchRecentSparkline(days: Int) async throws -> [SparklinePoint] {
        trend.map { SparklinePoint(date: $0.date, totalSeconds: $0.totalSeconds) }
    }
    func fetchSparkline(filters: FilterSnapshot) async throws -> [SparklinePoint] {
        trend.map { SparklinePoint(date: $0.date, totalSeconds: $0.totalSeconds) }
    }
    func fetchLongestSession(filters: FilterSnapshot) async throws -> LongestSession? { nil }
    func fetchHourlyAppUsage(for date: Date) async throws -> [HourlyAppUsage] { [] }
    func fetchDailyAppBreakdown(filters: FilterSnapshot, topN: Int) async throws -> [DailyAppBreakdown] { [] }

    // Phase 4 — analytics engine
    func fetchContextSwitchRate(filters: FilterSnapshot) async throws -> [ContextSwitchPoint] { [] }
    func fetchAppTransitions(filters: FilterSnapshot, limit: Int) async throws -> [AppTransition] { [] }
    func fetchWeekdayAverages(filters: FilterSnapshot) async throws -> [WeekdayAverage] { [] }
    func fetchPeriodComparison(current: FilterSnapshot, previous: FilterSnapshot) async throws -> PeriodDelta {
        PeriodDelta(currentTotalSeconds: 3600, previousTotalSeconds: 3000, percentChange: 20, currentAppsUsed: 5, previousAppsUsed: 4, appDeltas: [])
    }
    func generateInsights(filters: FilterSnapshot) async throws -> [Insight] { [] }
}
