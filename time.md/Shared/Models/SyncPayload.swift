import Foundation

/// Represents synced screen time data from a single device
struct DeviceSyncData: Codable, Identifiable, Sendable {
    var id: String { device.id }
    
    let device: DeviceInfo
    let lastSyncDate: Date
    let dailySummaries: [DailySyncSummary]
    let appUsage: [AppSyncUsage]
    let webBrowsing: WebBrowsingSyncData?
    
    /// Most recent day's total seconds
    var latestTotalSeconds: Double {
        dailySummaries.last?.totalSeconds ?? 0
    }
    
    /// Whether this device has web browsing data (Mac only)
    var hasWebBrowsingData: Bool {
        guard let web = webBrowsing else { return false }
        return web.totalVisits > 0
    }
}

/// Daily summary for sync (lightweight)
struct DailySyncSummary: Codable, Identifiable, Sendable {
    var id: Date { date }
    
    let date: Date
    let totalSeconds: Double
    let focusBlocks: Int
    let topAppBundleId: String?
    let topAppSeconds: Double?
}

/// App usage data for sync
struct AppSyncUsage: Codable, Identifiable, Sendable {
    var id: String { "\(bundleId)-\(date)" }
    
    let bundleId: String
    let displayName: String
    let category: String?
    let date: Date
    let totalSeconds: Double
    let sessionCount: Int
}

// MARK: - Web Browsing Sync Data

/// Web browsing summary for sync (from Mac browsers)
struct WebBrowsingSyncData: Codable, Sendable {
    let lastUpdated: Date
    let topDomains: [DomainSyncSummary]
    let dailyCounts: [DailyWebVisitCount]
    let totalVisits: Int
    
    static var empty: WebBrowsingSyncData {
        WebBrowsingSyncData(lastUpdated: .distantPast, topDomains: [], dailyCounts: [], totalVisits: 0)
    }
}

/// Domain summary for sync
struct DomainSyncSummary: Codable, Identifiable, Sendable {
    var id: String { domain }
    
    let domain: String
    let visitCount: Int
    let lastVisitTime: Date
}

/// Daily web visit count for sync
struct DailyWebVisitCount: Codable, Identifiable, Sendable {
    var id: Date { date }
    
    let date: Date
    let visitCount: Int
}

/// The complete sync payload exchanged via iCloud
struct SyncPayload: Codable, Sendable {
    static let currentVersion = 1
    
    let version: Int
    let lastModified: Date
    let devices: [DeviceSyncData]
    
    init(devices: [DeviceSyncData]) {
        self.version = Self.currentVersion
        self.lastModified = Date()
        self.devices = devices
    }
    
    /// Create empty payload
    static var empty: SyncPayload {
        SyncPayload(devices: [])
    }
    
    /// Merge another payload into this one (last-write-wins per device)
    func merging(_ other: SyncPayload) -> SyncPayload {
        var deviceMap: [String: DeviceSyncData] = [:]
        
        // Add all from self
        for device in devices {
            deviceMap[device.id] = device
        }
        
        // Merge from other (newer wins)
        for device in other.devices {
            if let existing = deviceMap[device.id] {
                if device.lastSyncDate > existing.lastSyncDate {
                    deviceMap[device.id] = device
                }
            } else {
                deviceMap[device.id] = device
            }
        }
        
        return SyncPayload(devices: Array(deviceMap.values))
    }
    
    /// Get data for a specific device
    func data(for deviceId: String) -> DeviceSyncData? {
        devices.first { $0.id == deviceId }
    }
    
    /// Get combined totals across all devices for a date range
    func combinedTotals(from startDate: Date, to endDate: Date) -> Double {
        devices.flatMap { $0.dailySummaries }
            .filter { $0.date >= startDate && $0.date <= endDate }
            .reduce(0) { $0 + $1.totalSeconds }
    }
}

// MARK: - File Operations

extension SyncPayload {
    /// Standard filename for sync file
    static let filename = "timeprint-sync.json"
    
    /// Encode to JSON data
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Decode from JSON data
    static func decode(from data: Data) throws -> SyncPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncPayload.self, from: data)
    }
    
    /// Save to a URL
    func save(to url: URL) throws {
        let data = try encode()
        try data.write(to: url, options: .atomic)
    }
    
    /// Load from a URL
    static func load(from url: URL) throws -> SyncPayload {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}

// MARK: - Aggregation Helpers

extension SyncPayload {
    /// Get daily totals across all devices
    func allDeviceDailyTotals(from startDate: Date, to endDate: Date) -> [Date: Double] {
        var totals: [Date: Double] = [:]
        
        let calendar = Calendar.current
        for device in devices {
            for summary in device.dailySummaries {
                let dayStart = calendar.startOfDay(for: summary.date)
                guard dayStart >= startDate && dayStart <= endDate else { continue }
                totals[dayStart, default: 0] += summary.totalSeconds
            }
        }
        
        return totals
    }
    
    /// Get per-device breakdown for a date
    func perDeviceBreakdown(for date: Date) -> [(device: DeviceInfo, seconds: Double)] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        
        return devices.compactMap { deviceData -> (DeviceInfo, Double)? in
            let dayTotal = deviceData.dailySummaries
                .filter { calendar.startOfDay(for: $0.date) == targetDay }
                .reduce(0) { $0 + $1.totalSeconds }
            
            guard dayTotal > 0 else { return nil }
            return (deviceData.device, dayTotal)
        }
    }
    
    /// Total screen time across all devices for today
    var todayTotalAllDevices: Double {
        let today = Calendar.current.startOfDay(for: Date())
        return allDeviceDailyTotals(from: today, to: today)[today] ?? 0
    }
}
