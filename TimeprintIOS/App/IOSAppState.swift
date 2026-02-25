import SwiftUI
import Combine
import UIKit
import FamilyControls

/// Main app state for iOS Timeprint
@MainActor
final class IOSAppState: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading = false
    @Published var error: String?
    @Published var showErrorAlert = false
    @Published var syncSucceeded = false
    
    // Device & Sync
    @Published var currentDevice: DeviceInfo
    @Published var syncPayload: SyncPayload = .empty
    @Published var lastSyncDate: Date?
    @Published var isSyncEnabled = false
    
    // Local Screen Time
    @Published var hasLocalScreenTimeAccess = false
    
    // Device Filtering
    @Published var selectedDeviceIds: Set<String> = [] {
        didSet {
            // Persist selection
            UserDefaults.standard.set(Array(selectedDeviceIds), forKey: "selectedDeviceIds")
            // Recalculate filtered data
            updateFilteredDashboardData()
        }
    }
    
    // Filtered Dashboard Data (based on selected synced devices only)
    @Published var filteredTodayTotalSeconds: Double = 0
    @Published var filteredWeekTotalSeconds: Double = 0
    @Published var filteredDailyAverage: Double = 0
    @Published var filteredRecentTrend: [SparklinePoint] = []
    @Published var filteredTopApps: [AppUsageSummary] = []
    
    // Dashboard Data
    @Published var todayTotalSeconds: Double = 0
    @Published var weekTotalSeconds: Double = 0
    @Published var dailyAverage: Double = 0
    @Published var focusBlocks: Int = 0
    
    // Trend
    @Published var recentTrend: [SparklinePoint] = []
    
    // Top Apps
    @Published var topApps: [AppUsageSummary] = []
    
    // MARK: - Private
    
    private let syncService: iCloudSyncService
    private let localDataService: IOSScreenTimeDataService
    private var syncObservation: (any Sendable)?
    private let hapticFeedback = UINotificationFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    // MARK: - Init
    
    init() {
        self.currentDevice = DeviceInfo.current()
        self.syncService = iCloudSyncService(containerIdentifier: "iCloud.com.codybontecou.Timeprint")
        self.localDataService = IOSScreenTimeDataService()
        
        // Restore persisted device selection
        if let savedIds = UserDefaults.standard.array(forKey: "selectedDeviceIds") as? [String] {
            self.selectedDeviceIds = Set(savedIds)
        }
        
        // Prepare haptic generators
        hapticFeedback.prepare()
        impactFeedback.prepare()
        
        // Check services availability
        Task {
            await checkSyncAvailability()
            await checkLocalScreenTimeAccess()
        }
    }
    
    /// Call this after onboarding completes to re-check authorization and refresh data
    func onboardingCompleted() async {
        print("[IOSAppState] Onboarding completed, re-checking authorization and refreshing data")
        await checkLocalScreenTimeAccess()
        await checkSyncAvailability()
    }
    
    // MARK: - Sync
    
    private func checkSyncAvailability() async {
        isSyncEnabled = syncService.isSyncAvailable
        
        if isSyncEnabled {
            await refreshFromCloud()
            startObservingChanges()
        }
    }
    
    private func checkLocalScreenTimeAccess() async {
        let status = AuthorizationCenter.shared.authorizationStatus
        hasLocalScreenTimeAccess = (status == .approved)
    }
    
    func refreshFromCloud() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            syncPayload = try await syncService.fetchPayload()
            lastSyncDate = Date()
            updateDashboardFromSync()
            
            // Success haptic
            hapticFeedback.notificationOccurred(.success)
            syncSucceeded = true
            
            // Hide success indicator after delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                syncSucceeded = false
            }
        } catch {
            self.error = error.localizedDescription
            self.showErrorAlert = true
            hapticFeedback.notificationOccurred(.error)
        }
    }
    
    func triggerSync() async {
        // Light haptic on tap
        impactFeedback.impactOccurred()
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 1. Fetch current cloud payload
            var remotePayload = try await syncService.fetchPayload()
            
            // 2. Build local device data if Screen Time access is granted
            if hasLocalScreenTimeAccess {
                let localData = try await buildLocalDeviceData()
                
                // 3. Merge local data into payload (replaces existing data for this device)
                var devices = remotePayload.devices.filter { $0.device.id != currentDevice.id }
                devices.append(localData)
                remotePayload = SyncPayload(devices: devices)
                
                // 4. Upload merged payload
                try await syncService.uploadPayload(remotePayload)
            }
            
            // 5. Update local state
            syncPayload = remotePayload
            lastSyncDate = Date()
            updateDashboardFromSync()
            
            // Success haptic
            hapticFeedback.notificationOccurred(.success)
            syncSucceeded = true
            
            // Hide success indicator after delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                syncSucceeded = false
            }
        } catch {
            self.error = error.localizedDescription
            self.showErrorAlert = true
            hapticFeedback.notificationOccurred(.error)
        }
    }
    
    /// Build sync-ready device data from local Screen Time
    private func buildLocalDeviceData() async throws -> DeviceSyncData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        
        let filters = FilterSnapshot(
            startDate: thirtyDaysAgo,
            endDate: today,
            granularity: .day
        )
        
        // Fetch focus days (daily summaries)
        let focusDays = try await localDataService.fetchFocusDays(filters: filters)
        
        // Fetch top apps
        let topApps = try await localDataService.fetchTopApps(filters: filters, limit: 20)
        
        // Convert to sync format
        let dailySummaries = focusDays.map { day in
            DailySyncSummary(
                date: day.date,
                totalSeconds: day.totalSeconds,
                focusBlocks: day.focusBlocks,
                topAppBundleId: topApps.first?.appName,
                topAppSeconds: topApps.first?.totalSeconds
            )
        }
        
        let appUsage = topApps.map { app in
            AppSyncUsage(
                bundleId: app.appName, // In iOS, we use display name as identifier
                displayName: app.appName,
                category: nil,
                date: today,
                totalSeconds: app.totalSeconds,
                sessionCount: app.sessionCount
            )
        }
        
        return DeviceSyncData(
            device: currentDevice,
            lastSyncDate: Date(),
            dailySummaries: dailySummaries,
            appUsage: appUsage,
            webBrowsing: nil // Web browsing data is Mac-only
        )
    }
    
    private func startObservingChanges() {
        syncObservation = syncService.observeChanges { [weak self] payload in
            Task { @MainActor in
                self?.syncPayload = payload
                self?.updateDashboardFromSync()
                self?.impactFeedback.impactOccurred()
            }
        }
    }
    
    // MARK: - Dashboard Updates
    
    private func updateDashboardFromSync() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        // Calculate totals from sync payload
        let todayTotals = syncPayload.allDeviceDailyTotals(from: today, to: today)
        todayTotalSeconds = todayTotals[today] ?? 0
        
        let weekTotals = syncPayload.allDeviceDailyTotals(from: weekAgo, to: today)
        weekTotalSeconds = weekTotals.values.reduce(0, +)
        
        let daysWithData = weekTotals.count
        dailyAverage = daysWithData > 0 ? weekTotalSeconds / Double(daysWithData) : 0
        
        // Calculate focus blocks from all devices
        focusBlocks = syncPayload.devices.flatMap { $0.dailySummaries }
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.focusBlocks }
        
        // Build trend from sync data
        var trendPoints: [SparklinePoint] = []
        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let seconds = weekTotals[date] ?? 0
            trendPoints.append(SparklinePoint(date: date, totalSeconds: seconds))
        }
        recentTrend = trendPoints
        
        // Update top apps
        updateTopApps()
        
        // Initialize device selection and update filtered data
        initializeDeviceSelectionIfNeeded()
        updateFilteredDashboardData()
    }
    
    private func updateTopApps() {
        // Aggregate app usage from all devices
        var appMap: [String: AppUsageSummary] = [:]
        
        for device in syncPayload.devices {
            for usage in device.appUsage {
                if var existing = appMap[usage.bundleId] {
                    existing = AppUsageSummary(
                        appName: existing.appName,
                        totalSeconds: existing.totalSeconds + usage.totalSeconds,
                        sessionCount: existing.sessionCount + usage.sessionCount
                    )
                    appMap[usage.bundleId] = existing
                } else {
                    appMap[usage.bundleId] = AppUsageSummary(
                        appName: usage.displayName,
                        totalSeconds: usage.totalSeconds,
                        sessionCount: usage.sessionCount
                    )
                }
            }
        }
        
        topApps = Array(appMap.values)
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(10)
            .map { $0 }
    }
    
    // MARK: - Device Filtering
    
    /// Initialize device selection when devices become available
    func initializeDeviceSelectionIfNeeded() {
        // If no devices are selected but we have devices, select all synced devices by default
        if selectedDeviceIds.isEmpty && !syncPayload.devices.isEmpty {
            selectedDeviceIds = Set(syncPayload.devices.map { $0.id })
        }
        // Also add current device (iPhone) if it has local screen time access
        // This allows showing the DeviceActivityReport section
        if hasLocalScreenTimeAccess {
            selectedDeviceIds.insert(currentDevice.id)
        }
    }
    
    /// Toggle a device's selection
    func toggleDevice(_ deviceId: String) {
        if selectedDeviceIds.contains(deviceId) {
            selectedDeviceIds.remove(deviceId)
        } else {
            selectedDeviceIds.insert(deviceId)
        }
    }
    
    /// Check if a device is selected
    func isDeviceSelected(_ deviceId: String) -> Bool {
        selectedDeviceIds.contains(deviceId)
    }
    
    /// Select all devices
    func selectAllDevices() {
        var ids = Set(syncPayload.devices.map { $0.id })
        if hasLocalScreenTimeAccess {
            ids.insert(currentDevice.id)
        }
        selectedDeviceIds = ids
    }
    
    /// Deselect all devices
    func deselectAllDevices() {
        selectedDeviceIds = []
    }
    
    /// Get selected devices data (synced devices only, not including current iPhone)
    var selectedDevices: [DeviceSyncData] {
        syncPayload.devices.filter { selectedDeviceIds.contains($0.id) }
    }
    
    /// Whether local iPhone is toggled on (for showing DeviceActivityReport)
    var includeLocalIPhoneData: Bool {
        hasLocalScreenTimeAccess && selectedDeviceIds.contains(currentDevice.id)
    }
    
    /// Update dashboard data based on selected synced devices only
    /// Note: iPhone data is NOT included in totals due to iOS sandbox restrictions
    /// iPhone data is displayed separately via DeviceActivityReport
    private func updateFilteredDashboardData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        // Filter to only selected SYNCED devices (NOT including current iPhone)
        // iPhone data cannot be exported programmatically due to iOS sandbox
        let filteredDevices = syncPayload.devices.filter { 
            selectedDeviceIds.contains($0.id) && $0.id != currentDevice.id
        }
        
        // Calculate today's total from selected synced devices only
        var todayTotal: Double = 0
        for device in filteredDevices {
            let deviceToday = device.dailySummaries
                .filter { calendar.isDateInToday($0.date) }
                .reduce(0) { $0 + $1.totalSeconds }
            todayTotal += deviceToday
        }
        
        filteredTodayTotalSeconds = todayTotal
        
        // Calculate week total from selected synced devices
        var weekTotals: [Date: Double] = [:]
        for device in filteredDevices {
            for summary in device.dailySummaries {
                let dayStart = calendar.startOfDay(for: summary.date)
                guard dayStart >= weekAgo && dayStart <= today else { continue }
                weekTotals[dayStart, default: 0] += summary.totalSeconds
            }
        }
        
        filteredWeekTotalSeconds = weekTotals.values.reduce(0, +)
        
        // Daily average
        let daysWithData = weekTotals.count
        filteredDailyAverage = daysWithData > 0 ? filteredWeekTotalSeconds / Double(daysWithData) : 0
        
        // Build trend from selected devices
        var trendPoints: [SparklinePoint] = []
        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let seconds = weekTotals[date] ?? 0
            trendPoints.append(SparklinePoint(date: date, totalSeconds: seconds))
        }
        filteredRecentTrend = trendPoints
        
        // Update filtered top apps (from synced devices only)
        updateFilteredTopApps(from: filteredDevices)
    }
    
    // MARK: - Filter-Based Data Methods
    
    /// Get total screen time for a date range with optional time-of-day filtering
    func getTotalSeconds(
        startDate: Date,
        endDate: Date,
        timeOfDayRanges: [TimeOfDayRange] = [],
        weekdayFilter: Set<Int> = []
    ) -> Double {
        let calendar = Calendar.current
        let filteredDevices = syncPayload.devices.filter {
            selectedDeviceIds.contains($0.id) && $0.id != currentDevice.id
        }
        
        var total: Double = 0
        
        for device in filteredDevices {
            for summary in device.dailySummaries {
                let dayStart = calendar.startOfDay(for: summary.date)
                
                // Check date range
                guard dayStart >= calendar.startOfDay(for: startDate) &&
                      dayStart <= calendar.startOfDay(for: endDate) else { continue }
                
                // Check weekday filter
                if !weekdayFilter.isEmpty {
                    let weekday = calendar.component(.weekday, from: summary.date) - 1 // 0-indexed
                    guard weekdayFilter.contains(weekday) else { continue }
                }
                
                // Note: time-of-day filtering would require hourly data which we don't have in summaries
                // For now, we include the full day's data if the day matches
                total += summary.totalSeconds
            }
        }
        
        return total
    }
    
    /// Get daily totals for a date range (for trend charts)
    func getDailyTotals(
        startDate: Date,
        endDate: Date,
        weekdayFilter: Set<Int> = []
    ) -> [SparklinePoint] {
        let calendar = Calendar.current
        let filteredDevices = syncPayload.devices.filter {
            selectedDeviceIds.contains($0.id) && $0.id != currentDevice.id
        }
        
        // Build a map of date -> total seconds
        var dailyTotals: [Date: Double] = [:]
        
        // Initialize all days in range
        var currentDate = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        while currentDate <= endDay {
            // Check weekday filter
            if weekdayFilter.isEmpty {
                dailyTotals[currentDate] = 0
            } else {
                let weekday = calendar.component(.weekday, from: currentDate) - 1
                if weekdayFilter.contains(weekday) {
                    dailyTotals[currentDate] = 0
                }
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Accumulate data from devices
        for device in filteredDevices {
            for summary in device.dailySummaries {
                let dayStart = calendar.startOfDay(for: summary.date)
                if dailyTotals.keys.contains(dayStart) {
                    dailyTotals[dayStart, default: 0] += summary.totalSeconds
                }
            }
        }
        
        // Convert to SparklinePoints sorted by date
        return dailyTotals
            .map { SparklinePoint(date: $0.key, totalSeconds: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    /// Get top apps for a date range
    func getTopApps(
        startDate: Date,
        endDate: Date,
        weekdayFilter: Set<Int> = [],
        limit: Int = 10
    ) -> [AppUsageSummary] {
        let calendar = Calendar.current
        let filteredDevices = syncPayload.devices.filter {
            selectedDeviceIds.contains($0.id) && $0.id != currentDevice.id
        }
        
        var appMap: [String: AppUsageSummary] = [:]
        
        for device in filteredDevices {
            for usage in device.appUsage {
                // Note: appUsage doesn't have per-day breakdown, so we include all if device has data in range
                // This is a limitation of the current data model
                if var existing = appMap[usage.bundleId] {
                    existing = AppUsageSummary(
                        appName: existing.appName,
                        totalSeconds: existing.totalSeconds + usage.totalSeconds,
                        sessionCount: existing.sessionCount + usage.sessionCount
                    )
                    appMap[usage.bundleId] = existing
                } else {
                    appMap[usage.bundleId] = AppUsageSummary(
                        appName: usage.displayName,
                        totalSeconds: usage.totalSeconds,
                        sessionCount: usage.sessionCount
                    )
                }
            }
        }
        
        return Array(appMap.values)
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(limit)
            .map { $0 }
    }
    
    private func updateFilteredTopApps(from devices: [DeviceSyncData]) {
        var appMap: [String: AppUsageSummary] = [:]
        
        for device in devices {
            for usage in device.appUsage {
                if var existing = appMap[usage.bundleId] {
                    existing = AppUsageSummary(
                        appName: existing.appName,
                        totalSeconds: existing.totalSeconds + usage.totalSeconds,
                        sessionCount: existing.sessionCount + usage.sessionCount
                    )
                    appMap[usage.bundleId] = existing
                } else {
                    appMap[usage.bundleId] = AppUsageSummary(
                        appName: usage.displayName,
                        totalSeconds: usage.totalSeconds,
                        sessionCount: usage.sessionCount
                    )
                }
            }
        }
        
        filteredTopApps = Array(appMap.values)
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(10)
            .map { $0 }
    }
    
    // MARK: - Error Handling
    
    func dismissError() {
        error = nil
        showErrorAlert = false
    }
}

// MARK: - Formatting Helpers

extension IOSAppState {
    var todayFormatted: String {
        TimeFormatters.formatDuration(todayTotalSeconds, style: .compact)
    }
    
    var weekFormatted: String {
        TimeFormatters.formatDuration(weekTotalSeconds, style: .hoursOnly)
    }
    
    var dailyAverageFormatted: String {
        TimeFormatters.formatDuration(dailyAverage, style: .compact)
    }
    
    var lastSyncFormatted: String {
        guard let date = lastSyncDate else { return "Never" }
        return TimeFormatters.relativeDate(date)
    }
    
    // Filtered data formatters (based on selected synced devices)
    var filteredTodayFormatted: String {
        TimeFormatters.formatDuration(filteredTodayTotalSeconds, style: .compact)
    }
    
    var filteredWeekFormatted: String {
        TimeFormatters.formatDuration(filteredWeekTotalSeconds, style: .hoursOnly)
    }
    
    var filteredDailyAverageFormatted: String {
        TimeFormatters.formatDuration(filteredDailyAverage, style: .compact)
    }
    
    /// Number of selected devices (including iPhone for display purposes)
    var selectedDeviceCount: Int {
        selectedDeviceIds.count
    }
    
    /// Whether all available devices are selected
    var allDevicesSelected: Bool {
        let allIds = Set(syncPayload.devices.map { $0.id })
        let localId = hasLocalScreenTimeAccess ? Set([currentDevice.id]) : Set<String>()
        let allAvailable = allIds.union(localId)
        return selectedDeviceIds == allAvailable && !allAvailable.isEmpty
    }
}
