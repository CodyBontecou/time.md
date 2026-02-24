import XCTest
@testable import TimeprintIOS

/// Tests for IOSScreenTimeDataService - the iOS Screen Time data layer
final class IOSScreenTimeDataServiceTests: XCTestCase {
    
    var dataStore: SharedDataStore!
    var sut: IOSScreenTimeDataService!
    
    override func setUp() async throws {
        try await super.setUp()
        dataStore = SharedDataStore()
        try await dataStore.clearAllData()
        sut = IOSScreenTimeDataService(dataStore: dataStore)
    }
    
    override func tearDown() async throws {
        try await dataStore.clearAllData()
        dataStore = nil
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Device Info Tests
    
    func testCurrentDevice_returnsValidDeviceInfo() async {
        let device = await sut.currentDevice
        
        XCTAssertFalse(device.id.isEmpty)
        XCTAssertFalse(device.name.isEmpty)
        XCTAssertEqual(device.platform, .iOS)
    }
    
    func testSupportsHistoricalData_returnsFalse() async {
        // iOS DeviceActivity only provides forward-looking data
        let supports = await sut.supportsHistoricalData
        XCTAssertFalse(supports)
    }
    
    // MARK: - Dashboard Summary Tests
    
    func testFetchDashboardSummary_withData_returnsCorrectTotals() async throws {
        // Given - seed data
        let deviceId = await sut.currentDevice.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let usage = StoredDailyUsage(
                deviceId: deviceId,
                date: date,
                totalSeconds: 3600 // 1 hour per day
            )
            try await dataStore.recordDailyUsage(usage)
        }
        
        // When
        let filters = FilterSnapshot(
            startDate: calendar.date(byAdding: .day, value: -6, to: today)!,
            endDate: today,
            granularity: .day
        )
        let summary = try await sut.fetchDashboardSummary(filters: filters)
        
        // Then
        XCTAssertEqual(summary.totalSeconds, 25200) // 7 hours
        XCTAssertEqual(summary.averageDailySeconds, 3600) // 1 hour average
    }
    
    func testFetchDashboardSummary_calculatesFocusBlocks() async throws {
        // Given - 2.5 hours = 6 focus blocks (25 min each)
        let deviceId = await sut.currentDevice.id
        let today = Calendar.current.startOfDay(for: Date())
        
        let usage = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 9000 // 2.5 hours
        )
        try await dataStore.recordDailyUsage(usage)
        
        // When
        let filters = FilterSnapshot(startDate: today, endDate: today, granularity: .day)
        let summary = try await sut.fetchDashboardSummary(filters: filters)
        
        // Then - 9000 / 1500 = 6 focus blocks
        XCTAssertEqual(summary.focusBlocks, 6)
    }
    
    // MARK: - Trend Tests
    
    func testFetchTrend_returnsSortedByDate() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Add data in reverse order
        for i in (0..<5).reversed() {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let usage = StoredDailyUsage(
                deviceId: deviceId,
                date: date,
                totalSeconds: Double((5 - i) * 1000)
            )
            try await dataStore.recordDailyUsage(usage)
        }
        
        // When
        let filters = FilterSnapshot(
            startDate: calendar.date(byAdding: .day, value: -4, to: today)!,
            endDate: today,
            granularity: .day
        )
        let trend = try await sut.fetchTrend(filters: filters)
        
        // Then - should be sorted by date ascending
        XCTAssertEqual(trend.count, 5)
        for i in 0..<(trend.count - 1) {
            XCTAssertLessThan(trend[i].date, trend[i + 1].date)
        }
    }
    
    // MARK: - Top Apps Tests
    
    func testFetchTopApps_returnsCorrectOrder() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let today = Calendar.current.startOfDay(for: Date())
        
        let appUsage = [
            StoredAppUsage(bundleId: "com.low", displayName: "Low App", totalSeconds: 100, pickupCount: 1),
            StoredAppUsage(bundleId: "com.high", displayName: "High App", totalSeconds: 5000, pickupCount: 10),
            StoredAppUsage(bundleId: "com.mid", displayName: "Mid App", totalSeconds: 2000, pickupCount: 5)
        ]
        
        let usage = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 7100,
            appUsage: appUsage
        )
        try await dataStore.recordDailyUsage(usage)
        
        // When
        let filters = FilterSnapshot(startDate: today, endDate: today, granularity: .day)
        let topApps = try await sut.fetchTopApps(filters: filters, limit: 10)
        
        // Then
        XCTAssertEqual(topApps.count, 3)
        XCTAssertEqual(topApps[0].appName, "High App")
        XCTAssertEqual(topApps[1].appName, "Mid App")
        XCTAssertEqual(topApps[2].appName, "Low App")
    }
    
    func testFetchTopApps_respectsLimit() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let today = Calendar.current.startOfDay(for: Date())
        
        var appUsage: [StoredAppUsage] = []
        for i in 1...20 {
            appUsage.append(StoredAppUsage(
                bundleId: "com.app.\(i)",
                displayName: "App \(i)",
                totalSeconds: Double(i * 100),
                pickupCount: i
            ))
        }
        
        let usage = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 21000,
            appUsage: appUsage
        )
        try await dataStore.recordDailyUsage(usage)
        
        // When
        let filters = FilterSnapshot(startDate: today, endDate: today, granularity: .day)
        let topApps = try await sut.fetchTopApps(filters: filters, limit: 5)
        
        // Then
        XCTAssertEqual(topApps.count, 5)
    }
    
    // MARK: - Focus Days Tests
    
    func testFetchFocusDays_calculatesBlocksPerDay() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Day 1: 1 hour (2 focus blocks)
        // Day 2: 2 hours (4 focus blocks)
        let records = [
            StoredDailyUsage(deviceId: deviceId, date: calendar.date(byAdding: .day, value: -1, to: today)!, totalSeconds: 3600),
            StoredDailyUsage(deviceId: deviceId, date: today, totalSeconds: 7200)
        ]
        try await dataStore.recordDailyUsage(records)
        
        // When
        let filters = FilterSnapshot(
            startDate: calendar.date(byAdding: .day, value: -1, to: today)!,
            endDate: today,
            granularity: .day
        )
        let focusDays = try await sut.fetchFocusDays(filters: filters)
        
        // Then
        XCTAssertEqual(focusDays.count, 2)
        
        let yesterday = focusDays.first { Calendar.current.isDate($0.date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) }
        let todayResult = focusDays.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
        
        XCTAssertEqual(yesterday?.focusBlocks, 2)
        XCTAssertEqual(todayResult?.focusBlocks, 4)
    }
    
    // MARK: - Heatmap Tests
    
    func testFetchHeatmap_aggregatesByHour() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let today = Calendar.current.startOfDay(for: Date())
        
        let hourlyUsage = [
            StoredHourlyUsage(hour: 9, totalSeconds: 1800),
            StoredHourlyUsage(hour: 10, totalSeconds: 3600),
            StoredHourlyUsage(hour: 14, totalSeconds: 2400)
        ]
        
        let usage = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 7800,
            appUsage: [],
            hourlyUsage: hourlyUsage
        )
        try await dataStore.recordDailyUsage(usage)
        
        // When
        let filters = FilterSnapshot(startDate: today, endDate: today, granularity: .day)
        let heatmap = try await sut.fetchHeatmap(filters: filters)
        
        // Then
        XCTAssertEqual(heatmap.count, 3)
        
        let hour10Cell = heatmap.first { $0.hour == 10 }
        XCTAssertEqual(hour10Cell?.totalSeconds, 3600)
    }
    
    // MARK: - Available Date Range Tests
    
    func testAvailableDateRange_returnsCorrectRange() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: today)!
        
        let records = [
            StoredDailyUsage(deviceId: deviceId, date: tenDaysAgo, totalSeconds: 1000),
            StoredDailyUsage(deviceId: deviceId, date: calendar.date(byAdding: .day, value: -5, to: today)!, totalSeconds: 2000),
            StoredDailyUsage(deviceId: deviceId, date: today, totalSeconds: 3000)
        ]
        try await dataStore.recordDailyUsage(records)
        
        // When
        let range = try await sut.availableDateRange()
        
        // Then
        XCTAssertNotNil(range)
        XCTAssertTrue(calendar.isDate(range!.lowerBound, inSameDayAs: tenDaysAgo))
        XCTAssertTrue(calendar.isDate(range!.upperBound, inSameDayAs: today))
    }
    
    func testAvailableDateRange_withNoData_returnsNil() async throws {
        let range = try await sut.availableDateRange()
        XCTAssertNil(range)
    }
    
    // MARK: - Convenience Method Tests
    
    func testTodayTotal_returnsCurrentDayTotal() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let today = Calendar.current.startOfDay(for: Date())
        
        let usage = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 5400
        )
        try await dataStore.recordDailyUsage(usage)
        
        // When
        let total = try await sut.todayTotal()
        
        // Then
        XCTAssertEqual(total, 5400)
    }
    
    func testWeekTotal_returnsSevenDayTotal() async throws {
        // Given
        let deviceId = await sut.currentDevice.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Add data for 7 days
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let usage = StoredDailyUsage(
                deviceId: deviceId,
                date: date,
                totalSeconds: 3600 // 1 hour each day
            )
            try await dataStore.recordDailyUsage(usage)
        }
        
        // When
        let total = try await sut.weekTotal()
        
        // Then
        XCTAssertEqual(total, 25200) // 7 hours
    }
}

// MARK: - Session Buckets Tests

extension IOSScreenTimeDataServiceTests {
    
    func testFetchSessionBuckets_estimatesFromPickups() async throws {
        // Given - app with 100 pickups and 1000 seconds = 10s avg session
        let deviceId = await sut.currentDevice.id
        let today = Calendar.current.startOfDay(for: Date())
        
        let appUsage = [
            StoredAppUsage(bundleId: "com.quick", displayName: "Quick App", totalSeconds: 1000, pickupCount: 100), // <1min avg
            StoredAppUsage(bundleId: "com.medium", displayName: "Medium App", totalSeconds: 6000, pickupCount: 20), // 5min avg
            StoredAppUsage(bundleId: "com.long", displayName: "Long App", totalSeconds: 36000, pickupCount: 10) // 1hr avg
        ]
        
        let usage = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 43000,
            appUsage: appUsage
        )
        try await dataStore.recordDailyUsage(usage)
        
        // When
        let filters = FilterSnapshot(startDate: today, endDate: today, granularity: .day)
        let buckets = try await sut.fetchSessionBuckets(filters: filters)
        
        // Then - should have all bucket labels
        XCTAssertEqual(buckets.count, 6)
        
        let bucketLabels = buckets.map { $0.label }
        XCTAssertTrue(bucketLabels.contains("< 1 min"))
        XCTAssertTrue(bucketLabels.contains("> 1 hour"))
    }
}
