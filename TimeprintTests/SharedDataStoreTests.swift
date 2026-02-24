import XCTest
@testable import TimeprintIOS

/// Tests for SharedDataStore - the App Group data persistence layer
final class SharedDataStoreTests: XCTestCase {
    
    var sut: SharedDataStore!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = SharedDataStore()
        // Clear any existing data
        try await sut.clearAllData()
    }
    
    override func tearDown() async throws {
        try await sut.clearAllData()
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Read/Write Tests
    
    func testLoadData_whenEmpty_returnsEmptyData() async throws {
        let data = try await sut.loadData()
        
        XCTAssertEqual(data.dailyUsage.count, 0)
        XCTAssertEqual(data.version, StoredUsageData.currentVersion)
    }
    
    func testRecordDailyUsage_storesData() async throws {
        // Given
        let usage = StoredDailyUsage(
            deviceId: "test-device-123",
            date: Date(),
            totalSeconds: 3600,
            appUsage: [],
            hourlyUsage: []
        )
        
        // When
        try await sut.recordDailyUsage(usage)
        
        // Then
        let data = try await sut.loadData()
        XCTAssertEqual(data.dailyUsage.count, 1)
        XCTAssertEqual(data.dailyUsage.first?.totalSeconds, 3600)
    }
    
    func testRecordDailyUsage_updatesExistingRecord() async throws {
        // Given
        let deviceId = "test-device-123"
        let date = Date()
        
        let initialUsage = StoredDailyUsage(
            deviceId: deviceId,
            date: date,
            totalSeconds: 1800,
            appUsage: [],
            hourlyUsage: []
        )
        try await sut.recordDailyUsage(initialUsage)
        
        // When - record updated usage for same day
        let updatedUsage = StoredDailyUsage(
            deviceId: deviceId,
            date: date,
            totalSeconds: 3600, // Updated value
            appUsage: [],
            hourlyUsage: []
        )
        try await sut.recordDailyUsage(updatedUsage)
        
        // Then - should have one record with updated value
        let data = try await sut.loadData()
        XCTAssertEqual(data.dailyUsage.count, 1)
        XCTAssertEqual(data.dailyUsage.first?.totalSeconds, 3600)
    }
    
    // MARK: - Fetch Tests
    
    func testFetchUsage_filtersByDateRange() async throws {
        // Given
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let deviceId = "test-device"
        
        // Create records for multiple days
        let records = [
            StoredDailyUsage(deviceId: deviceId, date: twoDaysAgo, totalSeconds: 1000),
            StoredDailyUsage(deviceId: deviceId, date: yesterday, totalSeconds: 2000),
            StoredDailyUsage(deviceId: deviceId, date: today, totalSeconds: 3000)
        ]
        try await sut.recordDailyUsage(records)
        
        // When - fetch only today
        let todayRecords = try await sut.fetchUsage(from: today, to: today, deviceId: deviceId)
        
        // Then
        XCTAssertEqual(todayRecords.count, 1)
        XCTAssertEqual(todayRecords.first?.totalSeconds, 3000)
    }
    
    func testFetchUsage_filtersByDeviceId() async throws {
        // Given
        let today = Calendar.current.startOfDay(for: Date())
        
        let iPhoneUsage = StoredDailyUsage(deviceId: "iphone-123", date: today, totalSeconds: 1000)
        let macUsage = StoredDailyUsage(deviceId: "mac-456", date: today, totalSeconds: 2000)
        
        try await sut.recordDailyUsage([iPhoneUsage, macUsage])
        
        // When
        let iPhoneRecords = try await sut.fetchUsage(from: today, to: today, deviceId: "iphone-123")
        
        // Then
        XCTAssertEqual(iPhoneRecords.count, 1)
        XCTAssertEqual(iPhoneRecords.first?.deviceId, "iphone-123")
    }
    
    func testTotalSeconds_aggregatesCorrectly() async throws {
        // Given
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let deviceId = "test-device"
        
        let records = [
            StoredDailyUsage(deviceId: deviceId, date: yesterday, totalSeconds: 1800),
            StoredDailyUsage(deviceId: deviceId, date: today, totalSeconds: 3600)
        ]
        try await sut.recordDailyUsage(records)
        
        // When
        let total = try await sut.totalSeconds(from: yesterday, to: today, deviceId: deviceId)
        
        // Then
        XCTAssertEqual(total, 5400) // 1800 + 3600
    }
    
    // MARK: - Top Apps Tests
    
    func testTopApps_returnsSortedByDuration() async throws {
        // Given
        let today = Calendar.current.startOfDay(for: Date())
        let deviceId = "test-device"
        
        let appUsage = [
            StoredAppUsage(bundleId: "com.app.low", displayName: "Low App", totalSeconds: 100, pickupCount: 1),
            StoredAppUsage(bundleId: "com.app.high", displayName: "High App", totalSeconds: 5000, pickupCount: 10),
            StoredAppUsage(bundleId: "com.app.mid", displayName: "Mid App", totalSeconds: 1000, pickupCount: 5)
        ]
        
        let record = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 6100,
            appUsage: appUsage,
            hourlyUsage: []
        )
        try await sut.recordDailyUsage(record)
        
        // When
        let topApps = try await sut.topApps(from: today, to: today, limit: 10, deviceId: deviceId)
        
        // Then
        XCTAssertEqual(topApps.count, 3)
        XCTAssertEqual(topApps[0].bundleId, "com.app.high")
        XCTAssertEqual(topApps[1].bundleId, "com.app.mid")
        XCTAssertEqual(topApps[2].bundleId, "com.app.low")
    }
    
    func testTopApps_respectsLimit() async throws {
        // Given
        let today = Calendar.current.startOfDay(for: Date())
        let deviceId = "test-device"
        
        var appUsage: [StoredAppUsage] = []
        for i in 1...20 {
            appUsage.append(StoredAppUsage(
                bundleId: "com.app.\(i)",
                displayName: "App \(i)",
                totalSeconds: Double(i * 100),
                pickupCount: i
            ))
        }
        
        let record = StoredDailyUsage(
            deviceId: deviceId,
            date: today,
            totalSeconds: 21000,
            appUsage: appUsage,
            hourlyUsage: []
        )
        try await sut.recordDailyUsage(record)
        
        // When
        let topApps = try await sut.topApps(from: today, to: today, limit: 5, deviceId: deviceId)
        
        // Then
        XCTAssertEqual(topApps.count, 5)
    }
    
    // MARK: - Pruning Tests
    
    func testPruneOldData_removesOldRecords() async throws {
        // Given
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let oldDate = calendar.date(byAdding: .day, value: -100, to: today)!
        let deviceId = "test-device"
        
        let records = [
            StoredDailyUsage(deviceId: deviceId, date: oldDate, totalSeconds: 1000),
            StoredDailyUsage(deviceId: deviceId, date: today, totalSeconds: 2000)
        ]
        try await sut.recordDailyUsage(records)
        
        // When - prune records older than 90 days
        try await sut.pruneOldData(olderThan: 90)
        
        // Then - only today's record should remain
        let data = try await sut.loadData()
        XCTAssertEqual(data.dailyUsage.count, 1)
        XCTAssertEqual(data.dailyUsage.first?.totalSeconds, 2000)
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentWrites_maintainsDataIntegrity() async throws {
        // Given
        let deviceId = "test-device"
        let today = Calendar.current.startOfDay(for: Date())
        
        // When - perform concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let usage = StoredDailyUsage(
                        deviceId: "\(deviceId)-\(i)",
                        date: today,
                        totalSeconds: Double(i * 100)
                    )
                    try? await self.sut.recordDailyUsage(usage)
                }
            }
        }
        
        // Then - all records should be present
        let data = try await sut.loadData()
        XCTAssertEqual(data.dailyUsage.count, 10)
    }
}

// MARK: - StoredUsageModels Tests

final class StoredUsageModelsTests: XCTestCase {
    
    func testStoredDailyUsage_idIsUnique() {
        // Given
        let date1 = Date()
        let date2 = Calendar.current.date(byAdding: .day, value: 1, to: date1)!
        
        let usage1 = StoredDailyUsage(deviceId: "device-1", date: date1, totalSeconds: 100)
        let usage2 = StoredDailyUsage(deviceId: "device-1", date: date2, totalSeconds: 200)
        let usage3 = StoredDailyUsage(deviceId: "device-2", date: date1, totalSeconds: 300)
        
        // Then
        XCTAssertNotEqual(usage1.id, usage2.id) // Same device, different day
        XCTAssertNotEqual(usage1.id, usage3.id) // Different device, same day
    }
    
    func testStoredUsageData_upsertUpdatesExisting() {
        // Given
        var data = StoredUsageData()
        let date = Date()
        
        let initial = StoredDailyUsage(deviceId: "device-1", date: date, totalSeconds: 100)
        data.upsert(initial)
        
        // When
        let updated = StoredDailyUsage(deviceId: "device-1", date: date, totalSeconds: 500)
        data.upsert(updated)
        
        // Then
        XCTAssertEqual(data.dailyUsage.count, 1)
        XCTAssertEqual(data.dailyUsage.first?.totalSeconds, 500)
    }
    
    func testStoredUsageData_usageForDateRange() {
        // Given
        var data = StoredUsageData()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<10 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            data.upsert(StoredDailyUsage(deviceId: "device-1", date: date, totalSeconds: Double(i * 100)))
        }
        
        // When - get last 3 days
        let threeDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let records = data.usage(from: threeDaysAgo, to: today, deviceId: "device-1")
        
        // Then
        XCTAssertEqual(records.count, 3)
    }
}
