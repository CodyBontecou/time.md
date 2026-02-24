import Foundation
@testable import TimeprintIOS

/// Mock data generators for Screen Time tests
enum MockScreenTimeData {
    
    // MARK: - Device Info
    
    static func mockDevice(
        id: String = "mock-device-123",
        name: String = "Mock iPhone",
        platform: DevicePlatform = .iOS
    ) -> DeviceInfo {
        DeviceInfo(
            id: id,
            name: name,
            model: "iPhone 15 Pro",
            osVersion: "17.2",
            platform: platform
        )
    }
    
    // MARK: - Daily Usage
    
    static func mockDailyUsage(
        deviceId: String = "mock-device-123",
        date: Date = Date(),
        totalSeconds: Double = 7200,
        appUsage: [StoredAppUsage] = [],
        hourlyUsage: [StoredHourlyUsage] = []
    ) -> StoredDailyUsage {
        StoredDailyUsage(
            deviceId: deviceId,
            date: date,
            totalSeconds: totalSeconds,
            appUsage: appUsage.isEmpty ? mockAppUsageList() : appUsage,
            hourlyUsage: hourlyUsage.isEmpty ? mockHourlyUsage() : hourlyUsage
        )
    }
    
    // MARK: - App Usage
    
    static func mockAppUsage(
        bundleId: String = "com.example.app",
        displayName: String = "Example App",
        categoryToken: String? = "Social",
        totalSeconds: Double = 1800,
        pickupCount: Int = 10,
        notificationCount: Int = 5
    ) -> StoredAppUsage {
        StoredAppUsage(
            bundleId: bundleId,
            displayName: displayName,
            categoryToken: categoryToken,
            totalSeconds: totalSeconds,
            pickupCount: pickupCount,
            notificationCount: notificationCount
        )
    }
    
    static func mockAppUsageList() -> [StoredAppUsage] {
        [
            mockAppUsage(bundleId: "com.instagram.app", displayName: "Instagram", categoryToken: "Social", totalSeconds: 3600, pickupCount: 25),
            mockAppUsage(bundleId: "com.apple.safari", displayName: "Safari", categoryToken: "Productivity", totalSeconds: 2400, pickupCount: 15),
            mockAppUsage(bundleId: "com.spotify.app", displayName: "Spotify", categoryToken: "Entertainment", totalSeconds: 1200, pickupCount: 5),
            mockAppUsage(bundleId: "com.apple.Messages", displayName: "Messages", categoryToken: "Social", totalSeconds: 900, pickupCount: 40),
            mockAppUsage(bundleId: "com.apple.mail", displayName: "Mail", categoryToken: "Productivity", totalSeconds: 600, pickupCount: 20)
        ]
    }
    
    // MARK: - Hourly Usage
    
    static func mockHourlyUsage() -> [StoredHourlyUsage] {
        // Simulate typical usage pattern: morning, lunch, evening peaks
        [
            StoredHourlyUsage(hour: 7, totalSeconds: 600),
            StoredHourlyUsage(hour: 8, totalSeconds: 900),
            StoredHourlyUsage(hour: 9, totalSeconds: 1200),
            StoredHourlyUsage(hour: 10, totalSeconds: 600),
            StoredHourlyUsage(hour: 12, totalSeconds: 1800),
            StoredHourlyUsage(hour: 13, totalSeconds: 900),
            StoredHourlyUsage(hour: 17, totalSeconds: 600),
            StoredHourlyUsage(hour: 18, totalSeconds: 1200),
            StoredHourlyUsage(hour: 19, totalSeconds: 1800),
            StoredHourlyUsage(hour: 20, totalSeconds: 2400),
            StoredHourlyUsage(hour: 21, totalSeconds: 1800),
            StoredHourlyUsage(hour: 22, totalSeconds: 900)
        ]
    }
    
    // MARK: - Sync Data
    
    static func mockDeviceSyncData(
        device: DeviceInfo? = nil,
        lastSyncDate: Date = Date(),
        dailySummaries: [DailySyncSummary] = [],
        appUsage: [AppSyncUsage] = []
    ) -> DeviceSyncData {
        let dev = device ?? mockDevice()
        return DeviceSyncData(
            device: dev,
            lastSyncDate: lastSyncDate,
            dailySummaries: dailySummaries.isEmpty ? mockDailySyncSummaries() : dailySummaries,
            appUsage: appUsage.isEmpty ? mockAppSyncUsage() : appUsage
        )
    }
    
    static func mockDailySyncSummaries(days: Int = 7) -> [DailySyncSummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return (0..<days).map { i in
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            return DailySyncSummary(
                date: date,
                totalSeconds: Double.random(in: 3600...10800), // 1-3 hours
                focusBlocks: Int.random(in: 2...8),
                topAppBundleId: "com.instagram.app",
                topAppSeconds: Double.random(in: 1200...3600)
            )
        }
    }
    
    static func mockAppSyncUsage() -> [AppSyncUsage] {
        let today = Calendar.current.startOfDay(for: Date())
        return [
            AppSyncUsage(bundleId: "com.instagram.app", displayName: "Instagram", category: "Social", date: today, totalSeconds: 3600, sessionCount: 25),
            AppSyncUsage(bundleId: "com.apple.safari", displayName: "Safari", category: "Productivity", date: today, totalSeconds: 2400, sessionCount: 15),
            AppSyncUsage(bundleId: "com.spotify.app", displayName: "Spotify", category: "Entertainment", date: today, totalSeconds: 1200, sessionCount: 5)
        ]
    }
    
    static func mockSyncPayload(deviceCount: Int = 2) -> SyncPayload {
        var devices: [DeviceSyncData] = []
        
        for i in 0..<deviceCount {
            let device = mockDevice(
                id: "device-\(i)",
                name: i == 0 ? "iPhone" : "MacBook Pro",
                platform: i == 0 ? .iOS : .macOS
            )
            devices.append(mockDeviceSyncData(device: device))
        }
        
        return SyncPayload(devices: devices)
    }
    
    // MARK: - Filter Snapshots
    
    static func todayFilter() -> FilterSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        return FilterSnapshot(startDate: today, endDate: today, granularity: .day)
    }
    
    static func weekFilter() -> FilterSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        return FilterSnapshot(startDate: weekAgo, endDate: today, granularity: .day)
    }
    
    static func monthFilter() -> FilterSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let monthAgo = calendar.date(byAdding: .day, value: -29, to: today)!
        return FilterSnapshot(startDate: monthAgo, endDate: today, granularity: .day)
    }
}

// MARK: - Test Data Seeding

extension SharedDataStore {
    /// Seed the store with mock data for testing
    func seedWithMockData(days: Int = 7, deviceId: String = "mock-device-123") async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var records: [StoredDailyUsage] = []
        for i in 0..<days {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            records.append(MockScreenTimeData.mockDailyUsage(
                deviceId: deviceId,
                date: date,
                totalSeconds: Double.random(in: 3600...10800)
            ))
        }
        
        try await recordDailyUsage(records)
    }
}
