import Charts
import SwiftUI

// MARK: - View

struct OverviewView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode
    @Environment(NavigationCoordinator.self) private var navigation
    @AppStorage("insightTickerAutoScroll") private var insightTickerAutoScroll: Bool = true
    @State private var summary = DashboardSummary(totalSeconds: 0, averageDailySeconds: 0, focusBlocks: 0)
    @State private var topApps: [AppUsageSummary] = []
    @State private var loadError: Error?
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false

    // Phase 2 — enriched overview state
    @State private var todaySummary: TodaySummary?
    @State private var periodSummary: PeriodSummary?
    @State private var sparklinePoints: [SparklinePoint] = []
    @State private var hourlyTrendPoints: [SparklinePoint] = []  // Hourly data for Day granularity
    @State private var longestSession: LongestSession?
    @State private var heatmapCells: [HeatmapCell] = []
    @State private var heatmapMax: Double = 0

    // Phase 4 — analytics insights
    @State private var insights: [Insight] = []
    @State private var periodDelta: PeriodDelta?
    
    // Phase 7 — cross-device sync
    @State private var syncPayload: SyncPayload = .empty
    @State private var lastSyncDate: Date?
    @State private var isSyncing: Bool = false
    
    // Loading state - progressive loading phases
    // Start with isLoadingPrimary = true so skeleton shows immediately on first render
    @State private var isLoadingPrimary: Bool = true
    @State private var isLoadingSecondary: Bool = false
    @State private var hasLoadedPrimary: Bool = false
    @State private var hasLoadedSecondary: Bool = false
    
    /// Show skeleton until both primary AND secondary data are loaded.
    /// The insight cards need periodSummary (from secondary), so we must wait
    /// for secondary to complete before showing the actual content.
    private var showSkeleton: Bool {
        !hasLoadedPrimary || !hasLoadedSecondary
    }

    // MARK: Computed helpers

    /// Whether the current view is showing hourly data (Day granularity)
    private var isHourlyMode: Bool { filters.granularity == .day }

    private var sparklineTitleForGranularity: String {
        switch filters.granularity {
        case .day: return "Daily Trend"
        case .week: return "Weekly Trend"
        case .month: return "Monthly Trend"
        case .year: return "Yearly Trend"
        }
    }
    
    /// Dynamic comparison label based on current period (e.g., "vs day before", "vs previous week")
    private var comparisonLabelForCurrentPeriod: String {
        let calendar = Calendar.current
        
        switch filters.granularity {
        case .day:
            if calendar.isDateInToday(filters.startDate) {
                return "vs yesterday"
            } else if calendar.isDateInYesterday(filters.startDate) {
                return "vs day before"
            } else {
                return "vs previous day"
            }
        case .week:
            if filters.isCurrentPeriod {
                return "vs last week"
            } else {
                return "vs previous week"
            }
        case .month:
            if filters.isCurrentPeriod {
                return "vs last month"
            } else {
                return "vs previous month"
            }
        case .year:
            if filters.isCurrentPeriod {
                return "vs last year"
            } else {
                return "vs previous year"
            }
        }
    }
    
    /// Dynamic context label based on current period (e.g., "yesterday", "that week")
    private var contextLabelForCurrentPeriod: String {
        let calendar = Calendar.current
        
        switch filters.granularity {
        case .day:
            if calendar.isDateInToday(filters.startDate) {
                return "today"
            } else if calendar.isDateInYesterday(filters.startDate) {
                return "yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return "on \(formatter.string(from: filters.startDate))"
            }
        case .week:
            if filters.isCurrentPeriod {
                return "this week"
            } else {
                return "that week"
            }
        case .month:
            if filters.isCurrentPeriod {
                return "this month"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                return "in \(formatter.string(from: filters.startDate))"
            }
        case .year:
            if filters.isCurrentPeriod {
                return "this year"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy"
                return "in \(formatter.string(from: filters.startDate))"
            }
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ─── Header Row: Title + Date | Granularity Picker ───
                headerSection
                
                if showSkeleton {
                    // ─── Skeleton loader during initial load ───
                    OverviewSkeletonView()
                } else {
                    // ─── Insight Cards Grid ───
                    insightCardsGrid

                    if let loadError {
                        DataLoadErrorView(error: loadError)
                    }

                    // ─── Insight Bar ───
                    if !insights.isEmpty {
                        insightBar
                    }

                    // ─── Content Area with integrated mode picker ───
                    contentSection
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showSkeleton)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .task(id: "\(filters.rangeLabel)\(filters.granularity.rawValue)\(filters.refreshToken)") {
            // Phase 1: Load primary data first (essential for initial render)
            await loadPrimary()

            // Phase 2: Load secondary data after primary completes
            await loadSecondary()
        }
        .task(id: "\(filters.rangeLabel)analytics\(filters.refreshToken)") {
            // Phase 3: Load analytics in background (lowest priority)
            // Small delay to let primary/secondary load first
            try? await Task.sleep(for: .milliseconds(100))
            await loadAnalytics()
        }
        .task {
            // Phase 4: Load sync payload only once on appear (not on filter changes)
            try? await Task.sleep(for: .milliseconds(200))
            await loadSyncPayload()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center) {
            // Left: Title + date + period comparison badge
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Overview")
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(BrutalTheme.textPrimary)

                    if let delta = periodDelta, delta.previousTotalSeconds > 0 {
                        let pct = delta.percentChange
                        let isUp = pct > 0
                        HStack(spacing: 3) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%.0f%%", abs(pct)))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .contentTransition(.numericText(value: abs(pct)))
                        }
                        .foregroundColor(isUp ? .red : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill((isUp ? Color.red : Color.green).opacity(0.12))
                        )
                        .transition(.scale.combined(with: .opacity))
                        .help("vs. previous period")
                        .accessibilityLabel(String(format: "%.0f percent %@ than previous period", abs(pct), isUp ? "more" : "less"))
                    }
                }

                Text(filters.rangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.8)
            }

        }
    }

    // MARK: - Insight Cards Grid

    private var insightCardsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
                // Row 1: Period delta, sparkline, peak hour, apps used
                navCard(.review) {
                    TodayDeltaCard(
                        todaySeconds: periodSummary?.totalSeconds ?? 0,
                        deltaPercent: periodSummary?.deltaPercent ?? 0,
                        periodLabel: filters.periodLabel.uppercased(),
                        comparisonLabel: comparisonLabelForCurrentPeriod
                    )
                }

                navCard(.review) {
                    if isHourlyMode {
                        HourlyTrendCard(
                            hourlyPoints: hourlyTrendPoints,
                            totalSeconds: periodSummary?.totalSeconds
                        )
                    } else {
                        SparklineCard(
                            points: sparklinePoints,
                            title: sparklineTitleForGranularity,
                            totalSeconds: periodSummary?.totalSeconds
                        )
                    }
                }

                navCard(.review) {
                    PeakHourCard(
                        hour: periodSummary?.peakHour ?? 0,
                        seconds: periodSummary?.peakHourSeconds ?? 0
                    )
                }

                navCard(.projects) {
                    AppsUsedCard(
                        count: periodSummary?.appsUsedCount ?? 0,
                        contextLabel: contextLabelForCurrentPeriod
                    )
                }

                // Row 2: Top app, longest session, mini heatmap, calendar preview
                navCard(.projects) {
                    TopAppSpotlightCard(
                        appName: periodSummary?.topAppName ?? "None",
                        seconds: periodSummary?.topAppSeconds ?? 0
                    )
                }

                navCard(.details) {
                    LongestSessionCard(
                        session: longestSession
                    )
                }

                navCard(.review) {
                    MiniHeatmapCard(
                        cells: heatmapCells,
                        maxSeconds: heatmapMax
                    )
                }

                navCard(.review) {
                    CalendarPreviewCard(
                        granularity: filters.granularity,
                        startDate: filters.startDate,
                        sparklinePoints: sparklinePoints,
                        hourlyPoints: hourlyTrendPoints,
                        periodLabel: filters.periodLabel
                    )
                }
                
                // Row 3: Device breakdown and sync status (when multiple devices)
                if syncPayload.devices.count > 1 {
                    DeviceBreakdownCard(
                        devices: syncPayload.devices,
                        selectedDate: filters.startDate
                    )
                    
                    SyncStatusCard(
                        lastSyncDate: lastSyncDate,
                        deviceCount: syncPayload.devices.count,
                        isSyncing: isSyncing
                    )
                }
            }
    }

    // MARK: - Nav Card Wrapper

    /// Wraps an insight card so tapping it navigates to the given destination.
    private func navCard<Content: View>(_ destination: NavigationDestination, @ViewBuilder content: () -> Content) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                navigation.selectedDestination = destination
            }
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Section (top apps chart + usage table)

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top Apps Chart
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TOP APPS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    topAppsChart
                }
            }

            // ─── APP USAGE TABLE ───
            Text("APP USAGE")
                .font(BrutalTheme.headingFont)
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1.5)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    if topApps.isEmpty {
                        Text("NO APP DATA FOR THIS PERIOD.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        appUsageTable
                    }
                }
            }
        }
    }

    // MARK: - Chart content

    private var topAppsChart: some View {
        let display = Array(topApps.prefix(8))

        return Chart(display) { app in
            BarMark(
                x: .value("Hours", app.totalSeconds / 3600),
                y: .value("App", AppNameDisplay.displayName(for: app.appName, mode: appNameDisplayMode))
            )
            .foregroundStyle(BrutalTheme.accent)
            .cornerRadius(4)
            .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                Text(DurationFormatter.short(app.totalSeconds))
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(name)
                            .font(BrutalTheme.captionMono)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .frame(height: max(CGFloat(display.count) * 36, 100))
    }

    // MARK: - App usage table

    private var appUsageTable: some View {
        let totalSeconds = topApps.reduce(0) { $0 + $1.totalSeconds }

        return VStack(spacing: 0) {
            // Header
            HStack {
                Text("#")
                    .frame(width: 28, alignment: .leading)
                Text("APP")
                Spacer()
                Text("TIME")
                    .frame(width: 80, alignment: .trailing)
                Text("SESS")
                    .frame(width: 52, alignment: .trailing)
                Text("%")
                    .frame(width: 48, alignment: .trailing)
            }
            .font(BrutalTheme.tableHeader)
            .foregroundColor(BrutalTheme.textTertiary)
            .tracking(0.5)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            Rectangle()
                .fill(BrutalTheme.borderStrong)
                .frame(height: 1)

            // Rows
            ForEach(Array(topApps.enumerated()), id: \.element.id) { index, app in
                let pct = totalSeconds > 0 ? app.totalSeconds / totalSeconds * 100 : 0

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(String(format: "%02d", index + 1))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 28, alignment: .leading)

                        #if os(macOS)
                        AppIconView(bundleID: app.appName, size: 16)
                        #endif

                        AppNameText(app.appName)
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        Text(DurationFormatter.short(app.totalSeconds))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .frame(width: 80, alignment: .trailing)

                        Text("\(app.sessionCount)")
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 52, alignment: .trailing)

                        Text(String(format: "%.1f%%", pct))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    // Percentage bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BrutalTheme.accent.opacity(0.2))
                            .frame(width: geo.size.width * max(pct / 100, 0), height: 3)
                    }
                    .frame(height: 3)

                    if index < topApps.count - 1 {
                        Rectangle()
                            .fill(BrutalTheme.border)
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }

    // MARK: - Date range pickers (preserved for future use)

    private var customDateRangeRow: some View {
        @Bindable var bindableFilters = filters

        return HStack(spacing: 12) {
            Spacer()

            Button {
                showStartDatePicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("FROM")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                    Text(bindableFilters.startDate, style: .date)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showStartDatePicker) {
                DatePicker("From", selection: $bindableFilters.startDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
            }

            Text("—")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)

            Button {
                showEndDatePicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("TO")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                    Text(bindableFilters.endDate, style: .date)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showEndDatePicker) {
                DatePicker("To", selection: $bindableFilters.endDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
            }
        }
    }

    // MARK: - Insight Bar

    private var insightBar: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("INSIGHTS")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                TickerScrollView(speed: 35, scrollMode: insightTickerAutoScroll ? .automatic : .manual) {
                    HStack(spacing: 12) {
                        ForEach(insights) { insight in
                            HStack(spacing: 8) {
                                Image(systemName: insight.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(insightColor(insight.sentiment))
                                    .frame(width: 20, height: 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(insightColor(insight.sentiment).opacity(0.12))
                                    )
                                Text(insight.text)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                            )
                        }
                    }
                    .padding(.trailing, insightTickerAutoScroll ? 40 : 0) // Gap for seamless loop (only needed for auto)
                }
                .frame(height: 36)
            }
        }
    }

    private func insightColor(_ sentiment: InsightSentiment) -> Color {
        switch sentiment {
        case .positive: .green
        case .negative: .red
        case .neutral: .gray
        }
    }

    // MARK: - Data loading (Progressive)

    /// Phase 1: Load essential data for initial render (summary + top apps)
    private func loadPrimary() async {
        isLoadingPrimary = true
        defer {
            isLoadingPrimary = false
            hasLoadedPrimary = true
        }
        
        do {
            loadError = nil
            let snapshot = filters.snapshot

            // Load summary and top apps in parallel - these are essential for initial render
            async let fetchedSummary = appEnvironment.dataService.fetchDashboardSummary(filters: snapshot)
            async let fetchedApps = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 30)

            summary = try await fetchedSummary
            topApps = try await fetchedApps
        } catch {
            loadError = error
            summary = DashboardSummary(totalSeconds: 0, averageDailySeconds: 0, focusBlocks: 0)
            topApps = []
        }
    }
    
    /// Phase 2: Load secondary data (longest session, insights cards data)
    private func loadSecondary() async {
        isLoadingSecondary = true
        defer {
            isLoadingSecondary = false
            hasLoadedSecondary = true
        }
        
        do {
            let snapshot = filters.snapshot

            // Load longest session
            longestSession = try await appEnvironment.dataService.fetchLongestSession(filters: snapshot)
            
            // Load insight card data
            async let periodFetch = appEnvironment.dataService.fetchPeriodSummary(filters: snapshot)
            async let sparklineFetch = appEnvironment.dataService.fetchSparkline(filters: snapshot)
            async let heatmapFetch = appEnvironment.dataService.fetchHeatmap(filters: snapshot)

            periodSummary = try await periodFetch
            sparklinePoints = try await sparklineFetch
            let fetchedCells = try await heatmapFetch
            heatmapCells = fetchedCells
            heatmapMax = fetchedCells.map(\.totalSeconds).max() ?? 0

            // Fetch hourly data when in Day granularity
            if isHourlyMode {
                let hourlyData = try await appEnvironment.dataService.fetchHourlyAppUsage(for: snapshot.startDate)
                
                // Aggregate by hour and convert to SparklinePoints
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: snapshot.startDate)
                
                var hourlyTotals: [Int: Double] = [:]
                for entry in hourlyData {
                    hourlyTotals[entry.hour, default: 0] += entry.totalSeconds
                }
                
                // Create points for all 24 hours (fill missing hours with 0)
                hourlyTrendPoints = (0..<24).compactMap { hour in
                    guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) else { return nil }
                    return SparklinePoint(date: hourDate, totalSeconds: hourlyTotals[hour, default: 0])
                }
            } else {
                hourlyTrendPoints = []
            }

            // Also update todaySummary for backwards compatibility (if needed elsewhere)
            todaySummary = TodaySummary(
                todayTotalSeconds: periodSummary?.totalSeconds ?? 0,
                yesterdayTotalSeconds: periodSummary?.previousTotalSeconds ?? 0,
                peakHour: periodSummary?.peakHour ?? 0,
                peakHourSeconds: periodSummary?.peakHourSeconds ?? 0,
                appsUsedCount: periodSummary?.appsUsedCount ?? 0,
                topAppName: periodSummary?.topAppName ?? "None",
                topAppSeconds: periodSummary?.topAppSeconds ?? 0
            )
        } catch {
            // Non-critical — insight cards gracefully show empty state
            longestSession = nil
            periodSummary = nil
            todaySummary = nil
            sparklinePoints = []
            hourlyTrendPoints = []
            heatmapCells = []
            heatmapMax = 0
        }
    }

    /// Phase 3: Load analytics data (insights, period comparison) - lowest priority
    private func loadAnalytics() async {
        // Wait for primary data to be available before generating insights
        guard hasLoadedPrimary else { return }
        
        do {
            let snapshot = filters.snapshot
            
            // Generate insights (this uses data from other queries)
            insights = try await appEnvironment.dataService.generateInsights(filters: snapshot)

            // Period comparison: compare current range to the same-length prior range
            let calendar = Calendar.current
            let rangeDays = calendar.dateComponents([.day], from: snapshot.startDate, to: snapshot.endDate).day ?? 7
            if let prevEnd = calendar.date(byAdding: .day, value: -1, to: snapshot.startDate),
               let prevStart = calendar.date(byAdding: .day, value: -rangeDays, to: prevEnd) {
                let previousSnapshot = FilterSnapshot(
                    startDate: prevStart, endDate: prevEnd,
                    granularity: snapshot.granularity,
                    selectedApps: snapshot.selectedApps,
                    selectedCategories: snapshot.selectedCategories,
                    selectedHeatmapCells: snapshot.selectedHeatmapCells
                )
                periodDelta = try await appEnvironment.dataService.fetchPeriodComparison(
                    current: snapshot, previous: previousSnapshot
                )
            }
        } catch {
            insights = []
            periodDelta = nil
        }
    }
    
    private func loadSyncPayload() async {
        guard let syncCoordinator = appEnvironment.syncCoordinator else {
            // No sync service available
            return
        }
        
        isSyncing = true
        
        // Run sync in a detached task to avoid blocking the main thread.
        // NSFileCoordinator operations can block, so we need to ensure
        // they don't run on the main actor's executor.
        let result: (payload: SyncPayload, date: Date)? = await Task.detached(priority: .utility) {
            do {
                // Perform sync to get latest data from all devices
                try await syncCoordinator.performSync()
                
                // Fetch the updated payload
                let payload = try await syncCoordinator.fetchPayload()
                return (payload, Date())
            } catch {
                // Sync failed - non-critical
                return nil
            }
        }.value
        
        // Update UI state on main actor
        if let result {
            syncPayload = result.payload
            lastSyncDate = result.date
        }
        isSyncing = false
    }
}
