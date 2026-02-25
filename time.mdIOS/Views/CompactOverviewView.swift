import SwiftUI
import Charts
import FamilyControls

/// Compact overview dashboard for iOS
struct CompactOverviewView: View {
    @EnvironmentObject private var appState: IOSAppState
    @StateObject private var filterStore = IOSFilterStore()
    @State private var showFilters = false
    
    /// Check if Screen Time tracking is authorized
    private var hasScreenTimeAccess: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Date navigator and filter controls
                filterControlsSection
                
                // Hero stat card (shows filtered data based on selected devices)
                heroCard
                
                // Active filters badge (if any)
                if filterStore.hasActiveFilters {
                    activeFiltersBadge
                }
                
                // Device selection summary (tappable to go to Devices tab)
                deviceSelectionBadge
                
                // Stats row
                statsRow
                
                // Trend chart (uses filtered data)
                trendCard
                
                // Top apps from selected devices
                if !filteredTopAppsData.isEmpty {
                    topAppsCard
                }
                
                // Sync status
                syncStatusCard
            }
            .padding()
        }
        .scrollIndicators(.never)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await appState.refreshFromCloud()
        }
        .onAppear {
            // Initialize device selection and refresh data
            appState.initializeDeviceSelectionIfNeeded()
        }
        .sheet(isPresented: $showFilters) {
            IOSTimeFiltersView(filterStore: filterStore)
        }
        .alert("Sync Error", isPresented: $appState.showErrorAlert) {
            Button("OK") {
                appState.dismissError()
            }
        } message: {
            Text(appState.error ?? "An unknown error occurred")
        }
        .overlay(alignment: .top) {
            if appState.syncSucceeded {
                syncSuccessBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: appState.syncSucceeded)
            }
        }
    }
    
    // MARK: - Sync Success Banner
    
    private var syncSuccessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Synced successfully")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }
    
    // MARK: - Filter Controls Section
    
    private var filterControlsSection: some View {
        // Date navigator with granularity and filter icon on same row
        HStack(spacing: 12) {
            // Previous period
            Button {
                withAnimation(.spring(response: 0.3)) {
                    filterStore.goToPreviousPeriod()
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Date range with granularity menu
            Menu {
                ForEach(TimeGranularity.allCases) { granularity in
                    Button {
                        withAnimation {
                            filterStore.granularity = granularity
                        }
                    } label: {
                        HStack {
                            Text(granularity.title)
                            if filterStore.granularity == granularity {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                if !filterStore.isCurrentPeriod {
                    Button {
                        withAnimation {
                            filterStore.goToCurrentPeriod()
                        }
                    } label: {
                        Label("Jump to Today", systemImage: "arrow.uturn.right")
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text(filterStore.dateRangeLabel)
                        .font(.headline)
                    
                    HStack(spacing: 4) {
                        Text(filterStore.granularity.title)
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            
            // Filter button (icon only)
            Button {
                showFilters = true
            } label: {
                Image(systemName: filterStore.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title2)
                    .foregroundStyle(filterStore.hasActiveFilters ? Color.accentColor : Color(.systemGray))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Next period
            Button {
                withAnimation(.spring(response: 0.3)) {
                    filterStore.goToNextPeriod()
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(filterStore.isCurrentPeriod ? Color(.systemGray4) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(filterStore.isCurrentPeriod)
        }
    }
    
    // MARK: - Active Filters Badge
    
    private var activeFiltersBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption)
                .foregroundStyle(.tint)
            
            Text("Filtering: \(filterStore.activeFiltersLabel ?? "")")
                .font(.caption)
                .fontWeight(.medium)
            
            Spacer()
            
            Button {
                withAnimation {
                    filterStore.clearAllFilters()
                }
            } label: {
                Text("Clear")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Hero Card
    
    private var heroCard: some View {
        VStack(spacing: 8) {
            Text(heroCardTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(1)
            
            Text(heroCardValue)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: appState.filteredTodayTotalSeconds)
            
            Text(heroCardSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heroCardTitle): \(heroCardValue)")
        .accessibilityHint("Shows your total screen time for \(filterStore.granularity.title.lowercased()) across selected devices")
    }
    
    private var heroCardTitle: String {
        switch filterStore.granularity {
        case .day:
            return filterStore.isCurrentPeriod ? "TODAY" : filterStore.dateRangeLabel.uppercased()
        case .week:
            return filterStore.isCurrentPeriod ? "THIS WEEK" : "WEEK OF \(weekStartLabel)"
        case .month:
            return filterStore.isCurrentPeriod ? "THIS MONTH" : filterStore.dateRangeLabel.uppercased()
        case .year:
            return filterStore.isCurrentPeriod ? "THIS YEAR" : filterStore.dateRangeLabel.uppercased()
        }
    }
    
    private var weekStartLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: filterStore.startDate).uppercased()
    }
    
    private var heroCardValue: String {
        // Use the filter store's date range and filters to get actual filtered data
        let total = appState.getTotalSeconds(
            startDate: filterStore.startDate,
            endDate: filterStore.endDate,
            timeOfDayRanges: filterStore.timeOfDayRanges,
            weekdayFilter: filterStore.selectedWeekdays
        )
        return TimeFormatters.formatDuration(total, style: .compact)
    }
    
    /// Filtered trend data based on current filter settings
    private var filteredTrendData: [SparklinePoint] {
        appState.getDailyTotals(
            startDate: filterStore.startDate,
            endDate: filterStore.endDate,
            weekdayFilter: filterStore.selectedWeekdays
        )
    }
    
    /// Filtered top apps based on current filter settings
    private var filteredTopAppsData: [AppUsageSummary] {
        appState.getTopApps(
            startDate: filterStore.startDate,
            endDate: filterStore.endDate,
            weekdayFilter: filterStore.selectedWeekdays,
            limit: 5
        )
    }
    
    private var heroCardSubtitle: String {
        var subtitle = "screen time"
        if filterStore.hasActiveFilters {
            subtitle += " (filtered)"
        }
        return subtitle
    }
    
    // MARK: - Device Selection Badge
    
    private var deviceSelectionBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: deviceBadgeIcon)
                .font(.subheadline)
                .foregroundStyle(.tint)
            
            Text(deviceBadgeText)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deviceBadgeText). Tap to manage device selection.")
        .accessibilityHint("Opens the Devices tab to toggle which devices are included")
    }
    
    private var deviceBadgeIcon: String {
        let count = appState.selectedDeviceCount
        if count == 0 {
            return "rectangle.slash"
        } else if count == 1 {
            if let deviceId = appState.selectedDeviceIds.first,
               let device = appState.syncPayload.devices.first(where: { $0.id == deviceId }) {
                return device.device.platform.icon
            } else if appState.includeLocalIPhoneData {
                return "iphone"
            }
            return "desktopcomputer"
        } else {
            return "macbook.and.iphone"
        }
    }
    
    private var deviceBadgeText: String {
        let count = appState.selectedDeviceCount
        if count == 0 {
            return "No devices selected"
        } else if count == 1 {
            if let deviceId = appState.selectedDeviceIds.first,
               let device = appState.syncPayload.devices.first(where: { $0.id == deviceId }) {
                return device.device.name
            } else if appState.includeLocalIPhoneData {
                return "This iPhone"
            }
            return "1 device"
        } else {
            return "\(count) devices combined"
        }
    }
    
    // MARK: - Stats Row
    
    private var statsRow: some View {
        HStack(spacing: 12) {
            statCell(
                title: periodLabel,
                value: filteredPeriodTotal,
                icon: "calendar"
            )
            
            statCell(
                title: "Daily Avg",
                value: filteredDailyAverage,
                icon: "chart.line.uptrend.xyaxis"
            )
            
            statCell(
                title: "Selected",
                value: "\(appState.selectedDeviceCount)",
                icon: "checkmark.circle"
            )
        }
    }
    
    private var periodLabel: String {
        switch filterStore.granularity {
        case .day: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .year: return "This Year"
        }
    }
    
    private var filteredPeriodTotal: String {
        let total = appState.getTotalSeconds(
            startDate: filterStore.startDate,
            endDate: filterStore.endDate,
            timeOfDayRanges: filterStore.timeOfDayRanges,
            weekdayFilter: filterStore.selectedWeekdays
        )
        return TimeFormatters.formatDuration(total, style: .compact)
    }
    
    private var filteredDailyAverage: String {
        let trendData = filteredTrendData
        let totalSeconds = trendData.reduce(0.0) { $0 + $1.totalSeconds }
        let daysWithData = trendData.filter { $0.totalSeconds > 0 }.count
        let average = daysWithData > 0 ? totalSeconds / Double(daysWithData) : 0
        return TimeFormatters.formatDuration(average, style: .compact)
    }
    
    private func statCell(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
    
    // MARK: - Trend Card
    
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trendCardTitle)
                    .font(.headline)
                
                Spacer()
                
                Text("\(appState.selectedDeviceCount) device\(appState.selectedDeviceCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if appState.selectedDeviceIds.isEmpty {
                Text("Select devices to see trends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else if filteredTrendData.isEmpty || filteredTrendData.allSatisfy({ $0.totalSeconds == 0 }) {
                Text("No data for this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(filteredTrendData) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.totalSeconds / 3600)
                    )
                    .foregroundStyle(.tint.opacity(0.3))
                    
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.totalSeconds / 3600)
                    )
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(TimeFormatters.dayOfWeek(date))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 150)
                .animation(.spring(response: 0.3), value: filteredTrendData.map { $0.totalSeconds })
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var trendCardTitle: String {
        switch filterStore.granularity {
        case .day:
            return "Today"
        case .week:
            return "Weekly Trend"
        case .month:
            return "Monthly Trend"
        case .year:
            return "Yearly Trend"
        }
    }
    
    // MARK: - Top Apps Card
    
    private var topAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Apps")
                    .font(.headline)
                
                Spacer()
                
                NavigationLink {
                    AppsListView()
                } label: {
                    Text("See All")
                        .font(.caption)
                }
            }
            
            ForEach(filteredTopAppsData, id: \.appName) { app in
                HStack {
                    // App icon placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray4))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Text(String(app.appName.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.appName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text("\(app.sessionCount) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(TimeFormatters.formatDuration(app.totalSeconds, style: .compact))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Sync Status Card
    
    private var syncStatusCard: some View {
        HStack {
            ZStack {
                Image(systemName: appState.isSyncEnabled ? "icloud.fill" : "icloud.slash")
                    .foregroundStyle(appState.isSyncEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                
                // Success checkmark overlay
                if appState.syncSucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .offset(x: 8, y: 8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isSyncEnabled ? "iCloud Sync Active" : "iCloud Sync Disabled")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Last sync: \(appState.lastSyncFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    Task { await appState.triggerSync() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                }
                .disabled(appState.isLoading)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Focus Blocks Extension

extension IOSAppState {
    var focusBlocksFormatted: String {
        "\(focusBlocks)"
    }
}

#Preview {
    NavigationStack {
        CompactOverviewView()
            .navigationBarHidden(true)
    }
    .environmentObject(IOSAppState())
}
