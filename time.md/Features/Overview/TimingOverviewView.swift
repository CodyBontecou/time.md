import Charts
import SwiftUI

// MARK: - Timing-style Overview

struct TimingOverviewView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode

    @State private var topApps: [AppUsageSummary] = []
    @State private var hourlyUsage: [HourlyAppUsage] = []
    @State private var periodSummary: PeriodSummary?
    @State private var periodDelta: PeriodDelta?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var selectedApp: String?
    @State private var hoveredApp: String?

    private var focusedApp: String? {
        selectedApp ?? hoveredApp
    }

    private var totalSeconds: Double {
        periodSummary?.totalSeconds ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                headerSection

                if isLoading {
                    OverviewSkeletonView()
                } else if let loadError {
                    DataLoadErrorView(error: loadError)
                } else {
                    summaryCards
                    timelineSection
                    topAppsSection
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .task(id: "\(filters.rangeLabel)\(filters.granularity.rawValue)\(filters.refreshToken)") {
            await loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Overview")
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundColor(BrutalTheme.textPrimary)

            if let delta = periodDelta, delta.previousTotalSeconds > 0 {
                let pct = delta.percentChange
                let isUp = pct > 0
                HStack(spacing: 4) {
                    Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                    Text(String(format: "%.0f%%", abs(pct)))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                .foregroundColor(isUp ? .red : .green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill((isUp ? Color.red : Color.green).opacity(0.12)))
            }

            Spacer()
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ]

        return LazyVGrid(columns: columns, spacing: 16) {
            TimingStatCard(
                title: "TOTAL TIME",
                value: DurationFormatter.short(totalSeconds),
                icon: "clock.fill",
                color: .blue
            )
            TimingStatCard(
                title: "DAILY AVG",
                value: DurationFormatter.short(periodSummary?.totalSeconds ?? 0),
                icon: "chart.line.uptrend.xyaxis",
                color: .green
            )
            TimingStatCard(
                title: "PEAK HOUR",
                value: formatHour(periodSummary?.peakHour ?? 0),
                icon: "flame.fill",
                color: .orange
            )
            TimingStatCard(
                title: "APPS USED",
                value: "\(periodSummary?.appsUsedCount ?? 0)",
                icon: "square.grid.2x2.fill",
                color: .purple
            )
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TIMELINE")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1.5)

            if hourlyUsage.isEmpty {
                Text("No activity recorded for this period.")
                    .font(.system(size: 14))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                // Hour labels
                timelineHourLabels

                // The timeline bar
                timelineBarContent

                // Legend
                timelineLegend
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BrutalTheme.surface.opacity(0.3))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedApp = nil
            }
        }
    }

    private var timelineHourLabels: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    if hour % 3 == 0 {
                        Text(formatHourShort(hour))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: width / 8, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 18)
    }

    private var timelineBarContent: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let barHeight: CGFloat = 48

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(BrutalTheme.surface.opacity(0.4))
                    .frame(height: barHeight)

                ForEach(hourlyUsage) { entry in
                    let startX = CGFloat(entry.hour) / 24.0 * width
                    let blockWidth = max(entry.totalSeconds / 3600.0 * (width / 24.0), 3)
                    let isFocused = focusedApp == nil || focusedApp == entry.appName

                    RoundedRectangle(cornerRadius: 4)
                        .fill(BrutalTheme.color(for: entry.appName))
                        .frame(width: blockWidth, height: isFocused && focusedApp != nil ? barHeight - 2 : barHeight - 6)
                        .opacity(isFocused ? 1.0 : 0.15)
                        .offset(x: startX)
                        .onHover { isHovering in
                            if selectedApp == nil {
                                hoveredApp = isHovering ? entry.appName : nil
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedApp == entry.appName {
                                    selectedApp = nil
                                } else {
                                    selectedApp = entry.appName
                                }
                            }
                        }
                        .help("\(AppNameDisplay.displayName(for: entry.appName, mode: appNameDisplayMode)): \(DurationFormatter.short(entry.totalSeconds))")
                }
            }
        }
        .frame(height: 48)
        .onHover { isHovering in
            if !isHovering && selectedApp == nil {
                hoveredApp = nil
            }
        }
    }

    private var timelineLegend: some View {
        let topAppNames = Array(
            Dictionary(grouping: hourlyUsage, by: \.appName)
                .mapValues { $0.reduce(0) { $0 + $1.totalSeconds } }
                .sorted { $0.value > $1.value }
                .prefix(6)
                .map(\.key)
        )

        return HStack(spacing: 16) {
            ForEach(topAppNames, id: \.self) { appName in
                let isFocused = focusedApp == nil || focusedApp == appName
                HStack(spacing: 6) {
                    Circle()
                        .fill(BrutalTheme.color(for: appName))
                        .frame(width: 10, height: 10)
                    AppNameText(appName)
                        .font(.system(size: 13, weight: isFocused && focusedApp != nil ? .bold : .medium))
                        .foregroundColor(isFocused ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
                }
                .opacity(isFocused ? 1.0 : 0.4)
                .onHover { isHovering in
                    if selectedApp == nil {
                        hoveredApp = isHovering ? appName : nil
                    }
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedApp == appName {
                            selectedApp = nil
                        } else {
                            selectedApp = appName
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Top Apps

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TOP APPS")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1.5)

            if topApps.isEmpty {
                Text("No app data for this period.")
                    .font(.system(size: 14))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topApps.prefix(10).enumerated()), id: \.element.id) { index, app in
                        appRow(app: app, index: index)
                        if index < min(topApps.count, 10) - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BrutalTheme.surface.opacity(0.3))
        )
    }

    private func appRow(app: AppUsageSummary, index: Int) -> some View {
        let pct = totalSeconds > 0 ? app.totalSeconds / totalSeconds : 0

        return HStack(spacing: 14) {
            #if os(macOS)
            AppIconView(bundleID: app.appName, size: 28)
            #endif

            AppNameText(app.appName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(BrutalTheme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BrutalTheme.surface.opacity(0.4))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BrutalTheme.color(for: app.appName))
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(width: 160, height: 8)

            Text(DurationFormatter.short(app.totalSeconds))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
                .frame(width: 70, alignment: .trailing)

            Text(String(format: "%.0f%%", pct * 100))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let fetchedApps = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 30)
            async let fetchedPeriod = appEnvironment.dataService.fetchPeriodSummary(filters: snapshot)
            async let fetchedHourly = appEnvironment.dataService.fetchHourlyAppUsage(for: snapshot.startDate)

            topApps = try await fetchedApps
            periodSummary = try await fetchedPeriod
            hourlyUsage = try await fetchedHourly

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
            loadError = error
        }
    }

    // MARK: - Helpers

    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h12) \(ampm)"
    }

    private func formatHourShort(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }
}

// MARK: - Stat Card

private struct TimingStatCard: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)

            Text(verbatim: value)
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundColor(BrutalTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BrutalTheme.surface.opacity(0.3))
        )
    }
}
