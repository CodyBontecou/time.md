import Foundation
import DeviceActivity
import os.log

/// iOS Screen Time data service that reads from the shared App Group data store.
/// Data is written by the DeviceActivityMonitor extension and read by this service.
actor IOSScreenTimeDataService: ScreenTimeProviding {
    
    // MARK: - Properties
    
    private let dataStore: SharedDataStore
    private let logger = Logger(subsystem: "com.codybontecou.Timeprint", category: "IOSScreenTimeDataService")
    private let device: DeviceInfo
    
    // MARK: - ScreenTimeProviding Properties
    
    nonisolated var currentDevice: DeviceInfo {
        device
    }
    
    nonisolated var supportsHistoricalData: Bool {
        // iOS DeviceActivity only provides data from when we started tracking
        false
    }
    
    // MARK: - Initialization
    
    init(dataStore: SharedDataStore = .shared) {
        self.dataStore = dataStore
        self.device = DeviceInfo.current()
    }
    
    // MARK: - ScreenTimeProviding Implementation
    
    func fetchDashboardSummary(filters: FilterSnapshot) async throws -> DashboardSummary {
        let records = try await dataStore.fetchUsage(
            from: filters.startDate,
            to: filters.endDate,
            deviceId: device.id
        )
        
        let totalSeconds = records.reduce(0) { $0 + $1.totalSeconds }
        let dayCount = max(1, records.count)
        let averageDaily = totalSeconds / Double(dayCount)
        
        // Calculate focus blocks (assuming 25min pomodoro blocks)
        let focusBlocks = records.reduce(0) { total, record in
            total + Int(record.totalSeconds / 1500) // 25 minutes
        }
        
        return DashboardSummary(
            totalSeconds: totalSeconds,
            averageDailySeconds: averageDaily,
            focusBlocks: focusBlocks
        )
    }
    
    func fetchTrend(filters: FilterSnapshot) async throws -> [TrendPoint] {
        let records = try await dataStore.fetchUsage(
            from: filters.startDate,
            to: filters.endDate,
            deviceId: device.id
        )
        
        // Group by granularity
        let calendar = Calendar.current
        var grouped: [Date: Double] = [:]
        
        for record in records {
            let key: Date
            switch filters.granularity {
            case .day:
                key = calendar.startOfDay(for: record.date)
            case .week:
                key = calendar.dateInterval(of: .weekOfYear, for: record.date)?.start ?? record.date
            case .month:
                key = calendar.dateInterval(of: .month, for: record.date)?.start ?? record.date
            case .year:
                key = calendar.dateInterval(of: .year, for: record.date)?.start ?? record.date
            }
            grouped[key, default: 0] += record.totalSeconds
        }
        
        return grouped.map { TrendPoint(date: $0.key, totalSeconds: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    func fetchTopApps(filters: FilterSnapshot, limit: Int) async throws -> [AppUsageSummary] {
        let topApps = try await dataStore.topApps(
            from: filters.startDate,
            to: filters.endDate,
            limit: limit,
            deviceId: device.id
        )
        
        return topApps.map { stored in
            AppUsageSummary(
                appName: stored.displayName,
                totalSeconds: stored.totalSeconds,
                sessionCount: stored.pickupCount
            )
        }
    }
    
    func fetchTopCategories(filters: FilterSnapshot, limit: Int) async throws -> [CategoryUsageSummary] {
        let records = try await dataStore.fetchUsage(
            from: filters.startDate,
            to: filters.endDate,
            deviceId: device.id
        )
        
        // Aggregate by category
        var categoryMap: [String: Double] = [:]
        
        for record in records {
            for app in record.appUsage {
                let category = app.categoryToken ?? "Other"
                categoryMap[category, default: 0] += app.totalSeconds
            }
        }
        
        return categoryMap.map { CategoryUsageSummary(category: $0.key, totalSeconds: $0.value) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(limit)
            .map { $0 }
    }
    
    func fetchHeatmap(filters: FilterSnapshot) async throws -> [HeatmapCell] {
        let records = try await dataStore.fetchUsage(
            from: filters.startDate,
            to: filters.endDate,
            deviceId: device.id
        )
        
        // Build heatmap from hourly data
        var heatmap: [String: Double] = [:]
        let calendar = Calendar.current
        
        for record in records {
            let weekday = calendar.component(.weekday, from: record.date)
            
            for hourlyUsage in record.hourlyUsage {
                let key = "\(weekday)-\(hourlyUsage.hour)"
                heatmap[key, default: 0] += hourlyUsage.totalSeconds
            }
        }
        
        return heatmap.map { key, seconds in
            let parts = key.split(separator: "-")
            let weekday = Int(parts[0]) ?? 1
            let hour = Int(parts[1]) ?? 0
            return HeatmapCell(weekday: weekday, hour: hour, totalSeconds: seconds)
        }
    }
    
    func fetchSessionBuckets(filters: FilterSnapshot) async throws -> [SessionBucket] {
        // DeviceActivity doesn't provide session-level data
        // Return estimated buckets based on pickup counts
        let records = try await dataStore.fetchUsage(
            from: filters.startDate,
            to: filters.endDate,
            deviceId: device.id
        )
        
        var buckets = [
            "< 1 min": 0,
            "1-5 min": 0,
            "5-15 min": 0,
            "15-30 min": 0,
            "30-60 min": 0,
            "> 1 hour": 0
        ]
        
        for record in records {
            for app in record.appUsage {
                // Estimate session distribution based on total time and pickup count
                let pickups = max(1, app.pickupCount)
                let avgSessionSeconds = app.totalSeconds / Double(pickups)
                
                let bucket: String
                switch avgSessionSeconds {
                case ..<60:
                    bucket = "< 1 min"
                case 60..<300:
                    bucket = "1-5 min"
                case 300..<900:
                    bucket = "5-15 min"
                case 900..<1800:
                    bucket = "15-30 min"
                case 1800..<3600:
                    bucket = "30-60 min"
                default:
                    bucket = "> 1 hour"
                }
                
                buckets[bucket, default: 0] += pickups
            }
        }
        
        let bucketOrder = ["< 1 min", "1-5 min", "5-15 min", "15-30 min", "30-60 min", "> 1 hour"]
        return bucketOrder.map { SessionBucket(label: $0, sessionCount: buckets[$0] ?? 0) }
    }
    
    func fetchFocusDays(filters: FilterSnapshot) async throws -> [FocusDay] {
        let records = try await dataStore.fetchUsage(
            from: filters.startDate,
            to: filters.endDate,
            deviceId: device.id
        )
        
        return records.map { record in
            // Estimate focus blocks (25-minute pomodoro intervals)
            let focusBlocks = Int(record.totalSeconds / 1500)
            return FocusDay(
                date: record.date,
                focusBlocks: focusBlocks,
                totalSeconds: record.totalSeconds
            )
        }
    }
    
    func availableDateRange() async throws -> ClosedRange<Date>? {
        let data = try await dataStore.loadData()
        guard !data.dailyUsage.isEmpty else { return nil }
        
        let dates = data.dailyUsage
            .filter { $0.deviceId == device.id }
            .map { $0.date }
        
        guard let minDate = dates.min(), let maxDate = dates.max() else {
            return nil
        }
        
        return minDate...maxDate
    }
}

// MARK: - Convenience Extension

extension IOSScreenTimeDataService {
    /// Quick access to today's total screen time
    func todayTotal() async throws -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        return try await dataStore.totalSeconds(for: today, deviceId: device.id)
    }
    
    /// Quick access to this week's total screen time
    func weekTotal() async throws -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        return try await dataStore.totalSeconds(from: weekAgo, to: today, deviceId: device.id)
    }
}
