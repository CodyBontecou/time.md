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
    @Published var localScreenTimeTotal: Double = 0
    
    // Dashboard Data
    @Published var todayTotalSeconds: Double = 0
    @Published var weekTotalSeconds: Double = 0
    @Published var dailyAverage: Double = 0
    @Published var focusBlocks: Int = 0
    @Published var currentStreak: Int = 0
    
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
        
        // Prepare haptic generators
        hapticFeedback.prepare()
        impactFeedback.prepare()
        
        // Check services availability
        Task {
            await checkSyncAvailability()
            await checkLocalScreenTimeAccess()
        }
        
        // Observe app foreground to refresh local Screen Time data
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocalDeviceActivityData()
            }
        }
        
        // Observe Darwin notification from DeviceActivityMonitor extension
        observeDeviceActivityUpdates()
    }
    
    private func observeDeviceActivityUpdates() {
        // Listen for Darwin notifications from the DeviceActivityMonitor extension
        let notificationName = CFNotificationName("com.codybontecou.Timeprint.monitorEvent" as CFString)
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let appState = Unmanaged<IOSAppState>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    appState.refreshLocalDeviceActivityData()
                }
            },
            notificationName.rawValue,
            nil,
            .deliverImmediately
        )
    }
    
    /// Refresh local device activity data (call when app becomes active or data updates)
    func refreshLocalDeviceActivityData() {
        guard hasLocalScreenTimeAccess else { return }
        readLocalDeviceActivityData()
    }
    
    /// Call this after onboarding completes to re-check authorization and refresh data
    func onboardingCompleted() async {
        print("[IOSAppState] Onboarding completed, re-checking authorization and refreshing data")
        await checkLocalScreenTimeAccess()
        await checkSyncAvailability()
        
        // Give DeviceActivityReport views time to render and populate data
        try? await Task.sleep(for: .seconds(2))
        readLocalDeviceActivityData()
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
        
        if hasLocalScreenTimeAccess {
            await refreshLocalScreenTime()
            // Also read top apps from DeviceActivityReport data
            readLocalDeviceActivityData()
        }
    }
    
    /// Read data that DeviceActivityReport extension has written to App Group UserDefaults
    func readLocalDeviceActivityData() {
        guard let appGroupDefaults = UserDefaults(suiteName: "group.com.codybontecou.Timeprint") else {
            print("[IOSAppState] Failed to access App Group UserDefaults")
            return
        }
        
        // Check when the report was last updated
        let lastUpdate = appGroupDefaults.object(forKey: "lastReportUpdate") as? Date
        print("[IOSAppState] Last DeviceActivityReport update: \(lastUpdate?.description ?? "never")")
        
        // Read total duration
        let reportTotal = appGroupDefaults.double(forKey: "todayTotalDuration")
        print("[IOSAppState] DeviceActivityReport todayTotalDuration: \(reportTotal)")
        
        if reportTotal > 0 {
            localScreenTimeTotal = reportTotal
            // Update today's total to include local iPhone data
            if hasLocalScreenTimeAccess {
                // Combine with cloud data or use local if higher
                let cloudToday = todayTotalSeconds
                todayTotalSeconds = max(cloudToday, reportTotal)
                print("[IOSAppState] Updated todayTotalSeconds to \(todayTotalSeconds) (cloud: \(cloudToday), local: \(reportTotal))")
            }
        }
        
        // Read top apps from DeviceActivityReport
        if let topAppsData = appGroupDefaults.array(forKey: "topApps") as? [[String: Any]] {
            print("[IOSAppState] Found \(topAppsData.count) apps from DeviceActivityReport")
            var localApps: [AppUsageSummary] = []
            for appDict in topAppsData {
                if let name = appDict["name"] as? String,
                   let duration = appDict["duration"] as? Double {
                    let pickups = appDict["pickups"] as? Int ?? 0
                    localApps.append(AppUsageSummary(
                        appName: name,
                        totalSeconds: duration,
                        sessionCount: pickups
                    ))
                }
            }
            
            // Merge with existing top apps (prioritize local data for iPhone)
            if !localApps.isEmpty {
                // For now, just use local apps if we have Screen Time access
                // In the future, could merge with cloud data more intelligently
                topApps = localApps
                print("[IOSAppState] Updated topApps with \(localApps.count) local apps")
            }
        } else {
            print("[IOSAppState] No topApps data found in UserDefaults")
        }
        
        // Read category durations if needed
        if let categoryData = appGroupDefaults.array(forKey: "categoryDurations") as? [[String: Any]] {
            // Could use this for category breakdown view
            print("[IOSAppState] Found \(categoryData.count) category durations from DeviceActivityReport")
        }
    }
    
    private func refreshLocalScreenTime() async {
        // First, try to read from the App Group UserDefaults where DeviceActivityReport writes
        if let appGroupDefaults = UserDefaults(suiteName: "group.com.codybontecou.Timeprint") {
            let reportTotal = appGroupDefaults.double(forKey: "todayTotalDuration")
            if reportTotal > 0 {
                localScreenTimeTotal = reportTotal
                // Also update today's total if it's higher than cloud data
                if reportTotal > todayTotalSeconds {
                    todayTotalSeconds = reportTotal
                }
                return
            }
        }
        
        // Fallback to SharedDataStore
        do {
            localScreenTimeTotal = try await localDataService.todayTotal()
        } catch {
            // Local data not available yet - this is expected initially
            localScreenTimeTotal = 0
        }
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
        
        // Calculate current streak (days with focus blocks)
        currentStreak = calculateCurrentStreak()
        
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
    }
    
    private func calculateCurrentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        
        // Get all daily summaries sorted by date descending
        let allSummaries = syncPayload.devices
            .flatMap { $0.dailySummaries }
            .sorted { $0.date > $1.date }
        
        while true {
            let dayTotal = allSummaries
                .filter { calendar.isDate($0.date, inSameDayAs: checkDate) }
                .reduce(0) { $0 + $1.totalSeconds }
            
            // Consider a day "active" if there's at least 5 minutes of screen time
            if dayTotal >= 300 {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        
        return streak
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
}
