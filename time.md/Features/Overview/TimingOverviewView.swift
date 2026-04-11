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

    private var totalSeconds: Double {
        periodSummary?.totalSeconds ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if isLoading {
                    OverviewSkeletonView()
                } else if let loadError {
                    DataLoadErrorView(error: loadError)
                } else {
                    summaryCards
                    timelineBar
                    topAppsBreakdown
                }
            }
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .task(id: "\(filters.rangeLabel)\(filters.granularity.rawValue)\(filters.refreshToken)") {
            await loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
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
                        }
                        .foregroundColor(isUp ? .red : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill((isUp ? Color.red : Color.green).opacity(0.12)))
                    }
                }

                Text(filters.rangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.8)
            }
            Spacer()
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            StatCard(
                title: "TOTAL TIME",
                value: DurationFormatter.short(totalSeconds),
                icon: "clock.fill",
                color: .blue
            )
            StatCard(
                title: "DAILY AVG",
                value: DurationFormatter.short(periodSummary?.totalSeconds ?? 0),
                icon: "chart.line.uptrend.xyaxis",
                color: .green
            )
            StatCard(
                title: "PEAK HOUR",
                value: formatHour(periodSummary?.peakHour ?? 0),
                icon: "flame.fill",
                color: .orange
            )
            StatCard(
                title: "APPS USED",
                value: "\(periodSummary?.appsUsedCount ?? 0)",
                icon: "square.grid.2x2.fill",
                color: .purple
            )
        }
    }

    // MARK: - Timeline Bar (Timing's signature feature)

    private var timelineBar: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("TIMELINE")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                if hourlyUsage.isEmpty {
                    Text("No activity recorded for this period.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    // Hour labels
                    timelineHourLabels

                    // Stacked color-coded timeline
                    timelineBarContent

                    // Legend
                    timelineLegend
                }
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
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: width / 8, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 14)
    }

    private var timelineBarContent: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let barHeight: CGFloat = 32

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 6)
                    .fill(BrutalTheme.surface.opacity(0.5))
                    .frame(height: barHeight)

                // App usage blocks
                ForEach(hourlyUsage) { entry in
                    let startX = CGFloat(entry.hour) / 24.0 * width
                    let blockWidth = max(entry.totalSeconds / 3600.0 * (width / 24.0), 2)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(BrutalTheme.color(for: entry.appName))
                        .frame(width: blockWidth, height: barHeight - 4)
                        .offset(x: startX)
                        .help("\(AppNameDisplay.displayName(for: entry.appName, mode: appNameDisplayMode)): \(DurationFormatter.short(entry.totalSeconds))")
                }
            }
        }
        .frame(height: 32)
    }

    private var timelineLegend: some View {
        let topAppNames = Array(
            Dictionary(grouping: hourlyUsage, by: \.appName)
                .mapValues { $0.reduce(0) { $0 + $1.totalSeconds } }
                .sorted { $0.value > $1.value }
                .prefix(6)
                .map(\.key)
        )

        return FlowLayout(spacing: 8) {
            ForEach(topAppNames, id: \.self) { appName in
                HStack(spacing: 4) {
                    Circle()
                        .fill(BrutalTheme.color(for: appName))
                        .frame(width: 8, height: 8)
                    AppNameText(appName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(BrutalTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Top Apps Breakdown

    private var topAppsBreakdown: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("TOP APPS")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                if topApps.isEmpty {
                    Text("No app data for this period.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(topApps.prefix(10).enumerated()), id: \.element.id) { index, app in
                        appRow(app: app, index: index)
                    }
                }
            }
        }
    }

    private func appRow(app: AppUsageSummary, index: Int) -> some View {
        let pct = totalSeconds > 0 ? app.totalSeconds / totalSeconds : 0

        return HStack(spacing: 10) {
            #if os(macOS)
            AppIconView(bundleID: app.appName, size: 20)
            #endif

            AppNameText(app.appName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(BrutalTheme.surface.opacity(0.5))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(BrutalTheme.color(for: app.appName))
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(width: 120, height: 6)

            Text(DurationFormatter.short(app.totalSeconds))
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textSecondary)
                .frame(width: 60, alignment: .trailing)

            Text(String(format: "%.0f%%", pct * 100))
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 4)
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

            // Period comparison
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

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                    Spacer()
                }

                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }
        }
    }
}
