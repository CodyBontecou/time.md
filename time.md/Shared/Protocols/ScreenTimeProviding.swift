import Foundation

/// Abstract protocol for screen time data access across platforms.
///
/// On macOS: Implemented by SQLiteScreenTimeDataService (reads the normalized usage table)
/// On iOS: Implemented by DeviceActivityDataService (uses ScreenTime framework)
///
/// This abstraction allows shared UI code to work with either backend.
protocol ScreenTimeProviding: Sendable {
    
    // MARK: - Summary Data
    
    /// Fetch dashboard summary for the given filters
    func fetchDashboardSummary(filters: FilterSnapshot) async throws -> DashboardSummary
    
    /// Fetch trend data (daily/weekly/monthly totals)
    func fetchTrend(filters: FilterSnapshot) async throws -> [TrendPoint]
    
    // MARK: - App & Category Data
    
    /// Fetch top apps by usage
    func fetchTopApps(filters: FilterSnapshot, limit: Int) async throws -> [AppUsageSummary]
    
    /// Fetch top categories by usage
    func fetchTopCategories(filters: FilterSnapshot, limit: Int) async throws -> [CategoryUsageSummary]
    
    // MARK: - Time Distribution
    
    /// Fetch heatmap data (hour × weekday)
    func fetchHeatmap(filters: FilterSnapshot) async throws -> [HeatmapCell]
    
    /// Fetch session duration distribution
    func fetchSessionBuckets(filters: FilterSnapshot) async throws -> [SessionBucket]
    
    // MARK: - Focus Data
    
    /// Fetch focus days data
    func fetchFocusDays(filters: FilterSnapshot) async throws -> [FocusDay]
    
    // MARK: - Device Info
    
    /// The device this service is running on
    var currentDevice: DeviceInfo { get }
    
    /// Whether this service can provide historical data
    var supportsHistoricalData: Bool { get }
    
    /// Date range of available data
    func availableDateRange() async throws -> ClosedRange<Date>?
}

// MARK: - Default Implementations

extension ScreenTimeProviding {
    var currentDevice: DeviceInfo {
        DeviceInfo.current()
    }
}

// MARK: - Capability Flags

/// Describes what a ScreenTimeProviding implementation can do
struct ScreenTimeCapabilities: OptionSet, Sendable {
    let rawValue: Int
    
    /// Can read historical data (days/weeks/months back)
    static let historicalData = ScreenTimeCapabilities(rawValue: 1 << 0)
    
    /// Can export raw data to CSV/JSON
    static let dataExport = ScreenTimeCapabilities(rawValue: 1 << 1)
    
    /// Can provide per-session granularity
    static let sessionGranularity = ScreenTimeCapabilities(rawValue: 1 << 2)
    
    /// Can provide hourly breakdown
    static let hourlyBreakdown = ScreenTimeCapabilities(rawValue: 1 << 3)
    
    /// Can track context switches (app→app transitions)
    static let contextSwitches = ScreenTimeCapabilities(rawValue: 1 << 4)
    
    /// Can sync data to other devices
    static let cloudSync = ScreenTimeCapabilities(rawValue: 1 << 5)
    
    /// macOS capabilities (full access via SQLite)
    static let macOS: ScreenTimeCapabilities = [
        .historicalData,
        .dataExport,
        .sessionGranularity,
        .hourlyBreakdown,
        .contextSwitches,
        .cloudSync
    ]
    
    /// iOS capabilities (limited via DeviceActivity framework)
    static let iOS: ScreenTimeCapabilities = [
        .cloudSync
    ]
    
    /// iOS with manual tracking enabled (forward-looking)
    static let iOSWithTracking: ScreenTimeCapabilities = [
        .hourlyBreakdown,
        .cloudSync
    ]
}

// MARK: - Error Types

/// Errors specific to screen time data access
enum ScreenTimeError: LocalizedError, Sendable {
    case notAuthorized
    case dataUnavailable
    case platformNotSupported
    case syncFailed(underlying: String)
    case dateRangeInvalid
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Screen Time access not authorized. Please grant permission in Settings."
        case .dataUnavailable:
            return "Screen Time data is not available on this device."
        case .platformNotSupported:
            return "This feature is not supported on the current platform."
        case .syncFailed(let underlying):
            return "Failed to sync screen time data: \(underlying)"
        case .dateRangeInvalid:
            return "The requested date range is invalid or no data exists for that period."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notAuthorized:
            return "Go to Settings > Screen Time and enable sharing."
        case .dataUnavailable:
            return "Ensure Screen Time is enabled on this device."
        case .platformNotSupported:
            return nil
        case .syncFailed:
            return "Check your internet connection and try again."
        case .dateRangeInvalid:
            return "Select a different date range."
        }
    }
}
