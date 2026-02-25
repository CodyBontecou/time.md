import SwiftUI

struct AppEnvironment: Sendable {
    let dataService: any ScreenTimeDataServing
    let exportCoordinator: any ExportCoordinating
    let syncCoordinator: SyncCoordinator?
    let featureFlags: FeatureFlags

    static let live: AppEnvironment = {
        let dataService = SQLiteScreenTimeDataService()
        let syncService = iCloudSyncService(containerIdentifier: "iCloud.com.codybontecou.Timeprint")
        
        // Create sync coordinator with adapter
        let syncCoordinator = SyncCoordinator(
            syncService: syncService,
            dataService: ScreenTimeDataAdapter(dataService: dataService)
        )
        
        return AppEnvironment(
            dataService: dataService,
            exportCoordinator: ExportCoordinator(dataService: dataService),
            syncCoordinator: syncCoordinator,
            featureFlags: .default
        )
    }()

    static let preview: AppEnvironment = {
        let dataService = SQLiteScreenTimeDataService()
        return AppEnvironment(
            dataService: dataService,
            exportCoordinator: ExportCoordinator(dataService: dataService),
            syncCoordinator: nil,
            featureFlags: .default
        )
    }()
}

/// Adapter to make ScreenTimeDataServing work with ScreenTimeProviding protocol
struct ScreenTimeDataAdapter: ScreenTimeProviding {
    let dataService: any ScreenTimeDataServing
    
    var supportsHistoricalData: Bool { true }
    
    func fetchDashboardSummary(filters: FilterSnapshot) async throws -> DashboardSummary {
        try await dataService.fetchDashboardSummary(filters: filters)
    }
    
    func fetchTrend(filters: FilterSnapshot) async throws -> [TrendPoint] {
        try await dataService.fetchTrend(filters: filters)
    }
    
    func fetchTopApps(filters: FilterSnapshot, limit: Int) async throws -> [AppUsageSummary] {
        try await dataService.fetchTopApps(filters: filters, limit: limit)
    }
    
    func fetchTopCategories(filters: FilterSnapshot, limit: Int) async throws -> [CategoryUsageSummary] {
        try await dataService.fetchTopCategories(filters: filters, limit: limit)
    }
    
    func fetchHeatmap(filters: FilterSnapshot) async throws -> [HeatmapCell] {
        try await dataService.fetchHeatmap(filters: filters)
    }
    
    func fetchSessionBuckets(filters: FilterSnapshot) async throws -> [SessionBucket] {
        try await dataService.fetchSessionBuckets(filters: filters)
    }
    
    func fetchFocusDays(filters: FilterSnapshot) async throws -> [FocusDay] {
        try await dataService.fetchFocusDays(filters: filters)
    }
    
    func availableDateRange() async throws -> ClosedRange<Date>? {
        // Default to last 90 days
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -90, to: end)!
        return start...end
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    static var defaultValue: AppEnvironment { .preview }
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
