import XCTest
@testable import time_md

final class SharedModelsTests: XCTestCase {
    // MARK: - TimeFormatters Tests

    func testFormatDurationCompact() {
        XCTAssertEqual(TimeFormatters.formatDuration(0, style: .compact), "0m")
        XCTAssertEqual(TimeFormatters.formatDuration(60, style: .compact), "1m")
        XCTAssertEqual(TimeFormatters.formatDuration(3600, style: .compact), "1h 0m")
        XCTAssertEqual(TimeFormatters.formatDuration(3660, style: .compact), "1h 1m")
        XCTAssertEqual(TimeFormatters.formatDuration(9000, style: .compact), "2h 30m")
    }

    func testFormatDurationFull() {
        XCTAssertEqual(TimeFormatters.formatDuration(60, style: .full), "1 minute")
        XCTAssertEqual(TimeFormatters.formatDuration(120, style: .full), "2 minutes")
        XCTAssertEqual(TimeFormatters.formatDuration(3600, style: .full), "1 hour 0 min")
        XCTAssertEqual(TimeFormatters.formatDuration(3660, style: .full), "1 hour 1 min")
    }

    func testFormatDurationHoursOnly() {
        XCTAssertEqual(TimeFormatters.formatDuration(0, style: .hoursOnly), "0.0h")
        XCTAssertEqual(TimeFormatters.formatDuration(1800, style: .hoursOnly), "0.5h")
        XCTAssertEqual(TimeFormatters.formatDuration(3600, style: .hoursOnly), "1.0h")
    }

    func testFormatHour() {
        XCTAssertEqual(TimeFormatters.formatHour(0), "12 AM")
        XCTAssertEqual(TimeFormatters.formatHour(12), "12 PM")
        XCTAssertEqual(TimeFormatters.formatHour(23), "11 PM")
    }

    // MARK: - DeviceInfo Tests

    func testDeviceInfoCurrentReturnsValidMacDevice() {
        let device = DeviceInfo.current()

        XCTAssertFalse(device.id.isEmpty)
        XCTAssertFalse(device.name.isEmpty)
        XCTAssertFalse(device.model.isEmpty)
        XCTAssertFalse(device.osVersion.isEmpty)
        XCTAssertEqual(device.platform, .macOS)
    }

    func testMacPlatformMetadata() {
        XCTAssertEqual(DeviceInfo.Platform.macOS.icon, "desktopcomputer")
        XCTAssertEqual(DeviceInfo.Platform.macOS.displayName, "Mac")
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
}
