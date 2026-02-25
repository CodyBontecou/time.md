import Foundation
import os.log

/// Thread-safe data store for sharing data between main app and extensions via App Group
actor SharedDataStore {
    
    // MARK: - Constants
    
    static let appGroupIdentifier = "group.com.codybontecou.Timeprint"
    private static let filename = "screen-time-data.json"
    private static let defaultsKey = "lastSyncTimestamp"
    
    // MARK: - Singleton
    
    static let shared = SharedDataStore()
    
    // MARK: - Properties
    
    private let fileURL: URL
    private let userDefaults: UserDefaults?
    private let logger = Logger(subsystem: "com.codybontecou.Timeprint", category: "SharedDataStore")
    
    private var cache: StoredUsageData?
    private var isDirty = false
    
    // MARK: - Initialization
    
    init() {
        // Get App Group container URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            self.fileURL = containerURL.appendingPathComponent(Self.filename)
        } else {
            // Fallback to app support directory (development/testing)
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let timeprintDir = appSupport.appendingPathComponent("time.md", isDirectory: true)
            try? FileManager.default.createDirectory(at: timeprintDir, withIntermediateDirectories: true)
            self.fileURL = timeprintDir.appendingPathComponent(Self.filename)
            logger.warning("App Group container not available, using fallback storage")
        }
        
        self.userDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)
    }
    
    // MARK: - Public API
    
    /// Load all stored usage data
    func loadData() async throws -> StoredUsageData {
        if let cache = cache {
            return cache
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.debug("No existing data file, returning empty data")
            return .empty
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode(StoredUsageData.self, from: data)
            cache = stored
            logger.debug("Loaded \(stored.dailyUsage.count) daily records")
            return stored
        } catch {
            logger.error("Failed to load data: \(error.localizedDescription)")
            throw SharedDataStoreError.loadFailed(error)
        }
    }
    
    /// Save usage data atomically
    func saveData(_ data: StoredUsageData) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let jsonData = try encoder.encode(data)
            
            // Write atomically
            try jsonData.write(to: fileURL, options: [.atomic])
            
            cache = data
            isDirty = false
            
            // Update last sync timestamp
            userDefaults?.set(Date(), forKey: Self.defaultsKey)
            
            logger.debug("Saved \(data.dailyUsage.count) daily records")
        } catch {
            logger.error("Failed to save data: \(error.localizedDescription)")
            throw SharedDataStoreError.saveFailed(error)
        }
    }
    
    /// Record daily usage (upserts existing record)
    func recordDailyUsage(_ usage: StoredDailyUsage) async throws {
        var data = try await loadData()
        data.upsert(usage)
        try await saveData(data)
    }
    
    /// Record multiple daily usage records at once
    func recordDailyUsage(_ records: [StoredDailyUsage]) async throws {
        var data = try await loadData()
        for record in records {
            data.upsert(record)
        }
        try await saveData(data)
    }
    
    /// Fetch usage for a date range
    func fetchUsage(from startDate: Date, to endDate: Date, deviceId: String? = nil) async throws -> [StoredDailyUsage] {
        let data = try await loadData()
        return data.usage(from: startDate, to: endDate, deviceId: deviceId)
    }
    
    /// Fetch usage for today
    func fetchTodayUsage(deviceId: String? = nil) async throws -> StoredDailyUsage? {
        let data = try await loadData()
        return data.usage(for: Date(), deviceId: deviceId)
    }
    
    /// Get total seconds for a date
    func totalSeconds(for date: Date, deviceId: String? = nil) async throws -> Double {
        let data = try await loadData()
        let records = data.usage(from: date, to: date, deviceId: deviceId)
        return records.reduce(0) { $0 + $1.totalSeconds }
    }
    
    /// Get total seconds for a date range
    func totalSeconds(from startDate: Date, to endDate: Date, deviceId: String? = nil) async throws -> Double {
        let data = try await loadData()
        let records = data.usage(from: startDate, to: endDate, deviceId: deviceId)
        return records.reduce(0) { $0 + $1.totalSeconds }
    }
    
    /// Get top apps by usage for a date range
    func topApps(from startDate: Date, to endDate: Date, limit: Int = 10, deviceId: String? = nil) async throws -> [StoredAppUsage] {
        let data = try await loadData()
        let records = data.usage(from: startDate, to: endDate, deviceId: deviceId)
        
        // Aggregate app usage across days
        var appMap: [String: StoredAppUsage] = [:]
        
        for record in records {
            for app in record.appUsage {
                if var existing = appMap[app.bundleId] {
                    existing = StoredAppUsage(
                        bundleId: existing.bundleId,
                        displayName: existing.displayName,
                        categoryToken: existing.categoryToken ?? app.categoryToken,
                        totalSeconds: existing.totalSeconds + app.totalSeconds,
                        pickupCount: existing.pickupCount + app.pickupCount,
                        notificationCount: existing.notificationCount + app.notificationCount
                    )
                    appMap[app.bundleId] = existing
                } else {
                    appMap[app.bundleId] = app
                }
            }
        }
        
        return Array(appMap.values)
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Prune old data (older than 90 days by default)
    func pruneOldData(olderThan days: Int = 90) async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var data = try await loadData()
        let countBefore = data.dailyUsage.count
        data.pruneRecords(olderThan: cutoffDate)
        let countAfter = data.dailyUsage.count
        
        if countBefore != countAfter {
            try await saveData(data)
            logger.info("Pruned \(countBefore - countAfter) old records")
        }
    }
    
    /// Clear all data (for testing/debugging)
    func clearAllData() async throws {
        try await saveData(.empty)
        logger.warning("Cleared all stored data")
    }
    
    /// Get last sync timestamp
    func lastSyncTimestamp() -> Date? {
        userDefaults?.object(forKey: Self.defaultsKey) as? Date
    }
    
    /// Invalidate cache (call when external changes might have occurred)
    func invalidateCache() {
        cache = nil
    }
}

// MARK: - Error Types

enum SharedDataStoreError: LocalizedError {
    case loadFailed(Error)
    case saveFailed(Error)
    case dataCorrupted
    case appGroupUnavailable
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Failed to load screen time data: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save screen time data: \(error.localizedDescription)"
        case .dataCorrupted:
            return "Screen time data appears to be corrupted"
        case .appGroupUnavailable:
            return "App Group container is not available"
        }
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    /// Convenience accessor for App Group UserDefaults
    static var appGroup: UserDefaults? {
        UserDefaults(suiteName: SharedDataStore.appGroupIdentifier)
    }
}
