import XCTest
@testable import time_md

final class SharedModelsTests: XCTestCase {
    
    // MARK: - SyncPayload Tests
    
    func testSyncPayloadEmptyReturnsEmptyDevices() {
        let payload = SyncPayload.empty
        XCTAssertTrue(payload.devices.isEmpty)
        XCTAssertEqual(payload.version, SyncPayload.currentVersion)
    }
    
    func testSyncPayloadMergingCombinesDevices() {
        let device1 = makeDeviceSyncData(id: "device-1", name: "MacBook Pro")
        let device2 = makeDeviceSyncData(id: "device-2", name: "iMac")
        
        let payload1 = SyncPayload(devices: [device1])
        let payload2 = SyncPayload(devices: [device2])
        
        let merged = payload1.merging(payload2)
        
        XCTAssertEqual(merged.devices.count, 2)
        XCTAssertTrue(merged.devices.contains { $0.id == "device-1" })
        XCTAssertTrue(merged.devices.contains { $0.id == "device-2" })
    }
    
    func testSyncPayloadMergingNewerDeviceWins() {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_100_000)
        
        let oldDevice = makeDeviceSyncData(id: "device-1", name: "Old Name", lastSyncDate: oldDate)
        let newDevice = makeDeviceSyncData(id: "device-1", name: "New Name", lastSyncDate: newDate)
        
        let payload1 = SyncPayload(devices: [oldDevice])
        let payload2 = SyncPayload(devices: [newDevice])
        
        let merged = payload1.merging(payload2)
        
        XCTAssertEqual(merged.devices.count, 1)
        XCTAssertEqual(merged.devices.first?.device.name, "New Name")
    }
    
    func testSyncPayloadAllDeviceDailyTotals() {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        
        let summaries1 = [
            DailySyncSummary(date: today, totalSeconds: 3600, focusBlocks: 2, topAppBundleId: nil, topAppSeconds: nil),
            DailySyncSummary(date: yesterday, totalSeconds: 1800, focusBlocks: 1, topAppBundleId: nil, topAppSeconds: nil)
        ]
        let summaries2 = [
            DailySyncSummary(date: today, totalSeconds: 2400, focusBlocks: 1, topAppBundleId: nil, topAppSeconds: nil)
        ]
        
        let device1 = makeDeviceSyncData(id: "device-1", name: "Mac 1", dailySummaries: summaries1)
        let device2 = makeDeviceSyncData(id: "device-2", name: "Mac 2", dailySummaries: summaries2)
        
        let payload = SyncPayload(devices: [device1, device2])
        let totals = payload.allDeviceDailyTotals(from: yesterday, to: today)
        
        XCTAssertEqual(totals[today], 6000) // 3600 + 2400
        XCTAssertEqual(totals[yesterday], 1800)
    }
    
    func testSyncPayloadTodayTotalAllDevices() {
        let today = Calendar.current.startOfDay(for: Date())
        
        let summaries1 = [
            DailySyncSummary(date: today, totalSeconds: 3600, focusBlocks: 2, topAppBundleId: nil, topAppSeconds: nil)
        ]
        let summaries2 = [
            DailySyncSummary(date: today, totalSeconds: 1800, focusBlocks: 1, topAppBundleId: nil, topAppSeconds: nil)
        ]
        
        let device1 = makeDeviceSyncData(id: "device-1", name: "Mac 1", dailySummaries: summaries1)
        let device2 = makeDeviceSyncData(id: "device-2", name: "Mac 2", dailySummaries: summaries2)
        
        let payload = SyncPayload(devices: [device1, device2])
        
        XCTAssertEqual(payload.todayTotalAllDevices, 5400) // 3600 + 1800
    }
    
    func testSyncPayloadEncodeDecode() throws {
        let device = makeDeviceSyncData(id: "test-device", name: "Test Mac")
        let payload = SyncPayload(devices: [device])
        
        let data = try payload.encode()
        let decoded = try SyncPayload.decode(from: data)
        
        XCTAssertEqual(decoded.devices.count, 1)
        XCTAssertEqual(decoded.devices.first?.id, "test-device")
        XCTAssertEqual(decoded.devices.first?.device.name, "Test Mac")
    }
    
    // MARK: - TimeFormatters Tests
    
    func testFormatDurationCompact() {
        XCTAssertEqual(TimeFormatters.formatDuration(0, style: .compact), "0m")
        XCTAssertEqual(TimeFormatters.formatDuration(60, style: .compact), "1m")
        XCTAssertEqual(TimeFormatters.formatDuration(3600, style: .compact), "1h 0m")
        XCTAssertEqual(TimeFormatters.formatDuration(3660, style: .compact), "1h 1m")
        XCTAssertEqual(TimeFormatters.formatDuration(7200, style: .compact), "2h 0m")
        XCTAssertEqual(TimeFormatters.formatDuration(9000, style: .compact), "2h 30m")
    }
    
    func testFormatDurationFull() {
        XCTAssertEqual(TimeFormatters.formatDuration(60, style: .full), "1 minute")
        XCTAssertEqual(TimeFormatters.formatDuration(120, style: .full), "2 minutes")
        XCTAssertEqual(TimeFormatters.formatDuration(3600, style: .full), "1 hour 0 min")
        XCTAssertEqual(TimeFormatters.formatDuration(3660, style: .full), "1 hour 1 min")
        XCTAssertEqual(TimeFormatters.formatDuration(7260, style: .full), "2 hours 1 min")
    }
    
    func testFormatDurationHoursOnly() {
        XCTAssertEqual(TimeFormatters.formatDuration(0, style: .hoursOnly), "0.0h")
        XCTAssertEqual(TimeFormatters.formatDuration(1800, style: .hoursOnly), "0.5h")
        XCTAssertEqual(TimeFormatters.formatDuration(3600, style: .hoursOnly), "1.0h")
        XCTAssertEqual(TimeFormatters.formatDuration(5400, style: .hoursOnly), "1.5h")
    }
    
    func testFormatDurationMinutesOnly() {
        XCTAssertEqual(TimeFormatters.formatDuration(0, style: .minutesOnly), "0m")
        XCTAssertEqual(TimeFormatters.formatDuration(60, style: .minutesOnly), "1m")
        XCTAssertEqual(TimeFormatters.formatDuration(3600, style: .minutesOnly), "60m")
    }
    
    func testFormatHours() {
        XCTAssertEqual(TimeFormatters.formatHours(0), "0.0")
        XCTAssertEqual(TimeFormatters.formatHours(1800), "0.5")
        XCTAssertEqual(TimeFormatters.formatHours(3600), "1.0")
        XCTAssertEqual(TimeFormatters.formatHours(9000), "2.5")
    }
    
    func testFormatChartValue() {
        XCTAssertEqual(TimeFormatters.formatChartValue(30), "30s")
        XCTAssertEqual(TimeFormatters.formatChartValue(120), "2m")
        XCTAssertEqual(TimeFormatters.formatChartValue(3600), "1.0h")
        XCTAssertEqual(TimeFormatters.formatChartValue(5400), "1.5h")
    }
    
    func testFormatHour() {
        XCTAssertEqual(TimeFormatters.formatHour(0), "12 AM")
        XCTAssertEqual(TimeFormatters.formatHour(1), "1 AM")
        XCTAssertEqual(TimeFormatters.formatHour(11), "11 AM")
        XCTAssertEqual(TimeFormatters.formatHour(12), "12 PM")
        XCTAssertEqual(TimeFormatters.formatHour(13), "1 PM")
        XCTAssertEqual(TimeFormatters.formatHour(23), "11 PM")
    }
    
    func testFormatWeekday() {
        XCTAssertEqual(TimeFormatters.formatWeekday(0), "Sun")
        XCTAssertEqual(TimeFormatters.formatWeekday(1), "Mon")
        XCTAssertEqual(TimeFormatters.formatWeekday(6), "Sat")
        XCTAssertEqual(TimeFormatters.formatWeekday(7), "?")
        XCTAssertEqual(TimeFormatters.formatWeekday(-1), "?")
    }
    
    func testFormatPercentChange() {
        XCTAssertEqual(TimeFormatters.formatPercentChange(0), "+0%")
        XCTAssertEqual(TimeFormatters.formatPercentChange(25), "+25%")
        XCTAssertEqual(TimeFormatters.formatPercentChange(-10), "-10%")
        XCTAssertEqual(TimeFormatters.formatPercentChange(100), "+100%")
    }
    
    func testFormatPercent() {
        XCTAssertEqual(TimeFormatters.formatPercent(0), "0%")
        XCTAssertEqual(TimeFormatters.formatPercent(50), "50%")
        XCTAssertEqual(TimeFormatters.formatPercent(100), "100%")
    }
    
    // MARK: - DeviceInfo Tests
    
    func testDeviceInfoCurrentReturnsValidDevice() {
        let device = DeviceInfo.current()
        
        XCTAssertFalse(device.id.isEmpty)
        XCTAssertFalse(device.name.isEmpty)
        XCTAssertFalse(device.model.isEmpty)
        XCTAssertFalse(device.osVersion.isEmpty)
        
        #if os(macOS)
        XCTAssertEqual(device.platform, .macOS)
        #else
        XCTAssertTrue([DevicePlatform.iOS, .iPadOS].contains(device.platform))
        #endif
    }
    
    func testDevicePlatformIcons() {
        XCTAssertEqual(DevicePlatform.macOS.icon, "desktopcomputer")
        XCTAssertEqual(DevicePlatform.iOS.icon, "iphone")
        XCTAssertEqual(DevicePlatform.iPadOS.icon, "ipad")
    }
    
    func testDevicePlatformDisplayNames() {
        XCTAssertEqual(DevicePlatform.macOS.displayName, "macOS")
        XCTAssertEqual(DevicePlatform.iOS.displayName, "iOS")
        XCTAssertEqual(DevicePlatform.iPadOS.displayName, "iPadOS")
    }
    
    // MARK: - SparklinePoint Tests
    
    func testSparklinePointIdentifiable() {
        let date = Date()
        let point = SparklinePoint(date: date, totalSeconds: 3600)
        
        XCTAssertEqual(point.id, date)
        XCTAssertEqual(point.totalSeconds, 3600)
    }
    
    // MARK: - FilterSnapshot Tests
    
    func testFilterSnapshotDayCount() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7))!
        
        let filters = FilterSnapshot(
            startDate: start,
            endDate: end,
            granularity: .day,
            selectedApps: [],
            selectedCategories: [],
            selectedHeatmapCells: []
        )
        
        XCTAssertEqual(filters.dayCount, 7)
    }
    
    // MARK: - Helpers
    
    private func makeDeviceSyncData(
        id: String,
        name: String,
        lastSyncDate: Date = Date(),
        dailySummaries: [DailySyncSummary] = [],
        appUsage: [AppSyncUsage] = []
    ) -> DeviceSyncData {
        let device = DeviceInfo(
            id: id,
            name: name,
            model: "Test Model",
            platform: .macOS,
            osVersion: "26.1"
        )
        
        return DeviceSyncData(
            device: device,
            lastSyncDate: lastSyncDate,
            dailySummaries: dailySummaries,
            appUsage: appUsage
        )
    }
}
