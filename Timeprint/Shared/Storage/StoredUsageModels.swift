import Foundation

// MARK: - Stored Usage Models

/// Daily usage record stored in App Group
struct StoredDailyUsage: Codable, Identifiable, Sendable {
    var id: String { "\(deviceId)-\(dateString)" }
    
    let deviceId: String
    let dateString: String  // ISO8601 date string (yyyy-MM-dd)
    let totalSeconds: Double
    let appUsage: [StoredAppUsage]
    let hourlyUsage: [StoredHourlyUsage]
    let lastUpdated: Date
    
    var date: Date {
        StoredDailyUsage.dateFormatter.date(from: dateString) ?? Date()
    }
    
    init(
        deviceId: String,
        date: Date,
        totalSeconds: Double,
        appUsage: [StoredAppUsage] = [],
        hourlyUsage: [StoredHourlyUsage] = []
    ) {
        self.deviceId = deviceId
        self.dateString = StoredDailyUsage.dateFormatter.string(from: date)
        self.totalSeconds = totalSeconds
        self.appUsage = appUsage
        self.hourlyUsage = hourlyUsage
        self.lastUpdated = Date()
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

/// Per-app usage record
struct StoredAppUsage: Codable, Identifiable, Sendable {
    var id: String { bundleId }
    
    let bundleId: String
    let displayName: String
    let categoryToken: String?
    let totalSeconds: Double
    let pickupCount: Int
    let notificationCount: Int
    
    init(
        bundleId: String,
        displayName: String,
        categoryToken: String? = nil,
        totalSeconds: Double,
        pickupCount: Int = 0,
        notificationCount: Int = 0
    ) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.categoryToken = categoryToken
        self.totalSeconds = totalSeconds
        self.pickupCount = pickupCount
        self.notificationCount = notificationCount
    }
}

/// Hourly usage breakdown
struct StoredHourlyUsage: Codable, Identifiable, Sendable {
    var id: Int { hour }
    
    let hour: Int  // 0-23
    let totalSeconds: Double
    
    init(hour: Int, totalSeconds: Double) {
        self.hour = hour
        self.totalSeconds = totalSeconds
    }
}

// MARK: - Storage Container

/// Container for all stored usage data
struct StoredUsageData: Codable, Sendable {
    static let currentVersion = 1
    
    let version: Int
    let lastModified: Date
    var dailyUsage: [StoredDailyUsage]
    
    init(dailyUsage: [StoredDailyUsage] = []) {
        self.version = Self.currentVersion
        self.lastModified = Date()
        self.dailyUsage = dailyUsage
    }
    
    static var empty: StoredUsageData {
        StoredUsageData()
    }
    
    /// Get usage for a specific date
    func usage(for date: Date, deviceId: String? = nil) -> StoredDailyUsage? {
        let dateString = formatDate(date)
        return dailyUsage.first { record in
            record.dateString == dateString &&
            (deviceId == nil || record.deviceId == deviceId)
        }
    }
    
    /// Get usage for a date range
    func usage(from startDate: Date, to endDate: Date, deviceId: String? = nil) -> [StoredDailyUsage] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        
        return dailyUsage.filter { record in
            let recordDate = record.date
            return recordDate >= start && recordDate <= end &&
                   (deviceId == nil || record.deviceId == deviceId)
        }
    }
    
    /// Add or update a daily usage record
    mutating func upsert(_ record: StoredDailyUsage) {
        if let index = dailyUsage.firstIndex(where: { $0.id == record.id }) {
            dailyUsage[index] = record
        } else {
            dailyUsage.append(record)
        }
    }
    
    /// Remove records older than the specified date
    mutating func pruneRecords(olderThan date: Date) {
        let cutoff = Calendar.current.startOfDay(for: date)
        dailyUsage.removeAll { $0.date < cutoff }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Category Mapping

/// Maps DeviceActivity category tokens to human-readable names
struct StoredCategoryMapping: Codable, Sendable {
    let token: String
    let displayName: String
    let systemCategory: String?  // e.g., "games", "social", "productivity"
}
