import Charts
import SwiftUI

private enum TrendChartMode: String, CaseIterable, Identifiable {
    case total = "Total"
    case stacked = "By App"

    var id: String { rawValue }
}

// MARK: - View

struct TrendsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode
    @State private var trend: [TrendPoint] = []
    @State private var dailyBreakdown: [DailyAppBreakdown] = []
    @State private var loadError: Error?
    @State private var hoveredDate: Date?
    @State private var brushedRange: ClosedRange<Date>?
    @State private var chartMode: TrendChartMode = .total
    
    /// Whether we're showing hourly breakdown (Day granularity)
    private var isHourlyMode: Bool { filters.granularity == .day }

    // Computed: top 5 app names for stacked chart
    private var top5Apps: [String] {
        var totals: [String: Double] = [:]
        for entry in dailyBreakdown {
            totals[entry.appName, default: 0] += entry.totalSeconds
        }
        return totals.sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
    }

    /// Deterministic color for an app name — consistent across all charts.
    private func colorForApp(_ app: String) -> Color {
        BrutalTheme.color(for: app, in: top5Apps)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trends")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(BrutalTheme.textPrimary)
                        Text(filters.rangeLabel.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .tracking(0.8)
                    }
                    Spacer()
                }

                if let loadError {
                    DataLoadErrorView(error: loadError)
                }

                // Controls row
                controlsRow

                // Main chart
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isHourlyMode ? "HOURLY USAGE" : "\(filters.granularity.title.uppercased()) USAGE")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)

                        if chartMode == .total {
                            totalChart
                        } else {
                            stackedChart
                        }
                    }
                }

                // Hover tooltip
                if let hoveredPoint {
                    GlassCard {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SELECTED")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .tracking(1)
                                Text(label(for: hoveredPoint.date))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(BrutalTheme.textPrimary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DURATION")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .tracking(1)
                                Text(DurationFormatter.short(hoveredPoint.totalSeconds))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textPrimary)
                            }
                            Spacer()
                        }
                    }
                }

                // Brush selection (only for non-hourly modes)
                if let brushedRange, !isHourlyMode {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BRUSH SELECTION")
                                .font(BrutalTheme.headingFont)
                                .foregroundColor(BrutalTheme.textSecondary)
                                .tracking(1)

                            Text("\(label(for: brushedRange.lowerBound)) → \(label(for: brushedRange.upperBound))")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textPrimary)

                            HStack(spacing: 8) {
                                Button("Apply to Date Range") {
                                    applyBrushToGlobalFilters(brushedRange)
                                }
                                .buttonStyle(.glass)
                                .tint(BrutalTheme.accent)

                                Button("Clear") {
                                    self.brushedRange = nil
                                }
                                .buttonStyle(.glass)
                                .tint(BrutalTheme.danger)
                            }
                        }
                    }
                }

                // Stacked legend
                if chartMode == .stacked && !top5Apps.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TOP APPS")
                                .font(BrutalTheme.headingFont)
                                .foregroundColor(BrutalTheme.textSecondary)
                                .tracking(1)

                            HStack(spacing: 16) {
                                ForEach(top5Apps, id: \.self) { app in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(colorForApp(app))
                                            .frame(width: 8, height: 8)
                                        AppNameText(app)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(BrutalTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .task(id: reloadKey) {
            await loadTrend()
        }
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: 12) {
            // Chart mode toggle
            HStack(spacing: 6) {
                ForEach(TrendChartMode.allCases) { mode in
                    let isActive = chartMode == mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { chartMode = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: isActive ? .bold : .medium, design: .monospaced))
                            .foregroundColor(isActive ? .white : BrutalTheme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .tint(isActive ? BrutalTheme.accent : .clear)
                }
            }

            Spacer()
        }
    }

    // MARK: - Total chart

    private var totalChart: some View {
        Chart {
            ForEach(trend) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Seconds", point.totalSeconds)
                )
                .foregroundStyle(.teal.opacity(0.2).gradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Seconds", point.totalSeconds)
                )
                .foregroundStyle(.teal)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            // Hover indicator
            if let hoveredPoint {
                RuleMark(x: .value("Date", hoveredPoint.date))
                    .foregroundStyle(BrutalTheme.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                PointMark(
                    x: .value("Date", hoveredPoint.date),
                    y: .value("Seconds", hoveredPoint.totalSeconds)
                )
                .symbolSize(60)
                .foregroundStyle(.teal)
            }
        }
        .chartYScale(domain: 0...(trend.map(\.totalSeconds).max() ?? 0) * 1.1)
        .animation(.easeInOut(duration: 0.4), value: trend.map(\.totalSeconds))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(BrutalTheme.border)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(DurationFormatter.short(seconds))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(BrutalTheme.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortAxisLabel(date))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            updateHoveredDate(locationX: location.x, proxy: proxy, geometry: geometry)
                        case .ended:
                            hoveredDate = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateBrush(
                                    startX: value.startLocation.x,
                                    currentX: value.location.x,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            }
                    )
            }
        }
        .frame(height: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChartAccessibility.trendSummary(
            points: trend.map { ($0.date, $0.totalSeconds) },
            label: "Screen time trend"
        ))
    }

    // MARK: - Stacked area chart

    private var stackedChart: some View {
        let filtered = dailyBreakdown.filter { top5Apps.contains($0.appName) }

        return Chart(filtered) { entry in
            AreaMark(
                x: .value("Date", entry.date),
                y: .value("Seconds", entry.totalSeconds)
            )
            .foregroundStyle(by: .value("App", AppNameDisplay.displayName(for: entry.appName, mode: appNameDisplayMode)))
            .interpolationMethod(.catmullRom)
        }
        .chartForegroundStyleScale(
            domain: top5Apps.map { AppNameDisplay.displayName(for: $0, mode: appNameDisplayMode) },
            range: top5Apps.map { colorForApp($0) }
        )
        .animation(.easeInOut(duration: 0.4), value: dailyBreakdown.map(\.totalSeconds))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(BrutalTheme.border)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(DurationFormatter.short(seconds))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    .foregroundStyle(BrutalTheme.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortAxisLabel(date))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                }
            }
        }
        .frame(height: 340)
    }

    // MARK: - Helpers

    private var reloadKey: String {
        [
            String(filters.startDate.timeIntervalSince1970),
            String(filters.endDate.timeIntervalSince1970),
            filters.granularity.rawValue,
        ].joined(separator: "::")
    }

    private var hoveredPoint: TrendPoint? {
        guard let hoveredDate else { return nil }
        return trend.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
    }

    private func updateHoveredDate(locationX: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { hoveredDate = nil; return }
        let plotRect = geometry[plotFrame]
        let relativeX = locationX - plotRect.origin.x
        guard relativeX >= 0, relativeX <= plotRect.width,
              let date: Date = proxy.value(atX: relativeX) else { hoveredDate = nil; return }
        hoveredDate = date
    }

    private func updateBrush(startX: CGFloat, currentX: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotRect = geometry[plotFrame]
        guard let startDate: Date = proxy.value(atX: startX - plotRect.origin.x),
              let currentDate: Date = proxy.value(atX: currentX - plotRect.origin.x) else { return }
        let lower = min(startDate, currentDate)
        let upper = max(startDate, currentDate)
        brushedRange = abs(upper.timeIntervalSince(lower)) < 60 ? nil : lower...upper
    }

    private func applyBrushToGlobalFilters(_ range: ClosedRange<Date>) {
        let calendar = Calendar.current
        filters.startDate = calendar.startOfDay(for: range.lowerBound)
        filters.endDate = calendar.startOfDay(for: range.upperBound)
    }

    private func label(for date: Date) -> String {
        let formatter = DateFormatter()
        if isHourlyMode {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateStyle = .medium
        }
        return formatter.string(from: date)
    }

    private func shortAxisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        if isHourlyMode {
            formatter.dateFormat = "ha"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    private func loadTrend() async {
        do {
            loadError = nil
            let snapshot = filters.snapshot

            if isHourlyMode {
                // Fetch hourly breakdown for Day view
                let hourlyData = try await appEnvironment.dataService.fetchHourlyAppUsage(for: snapshot.startDate)
                
                // Convert to TrendPoints (aggregated by hour)
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: snapshot.startDate)
                
                var hourlyTotals: [Int: Double] = [:]
                var hourlyAppBreakdown: [DailyAppBreakdown] = []
                
                for entry in hourlyData {
                    hourlyTotals[entry.hour, default: 0] += entry.totalSeconds
                    
                    // Create a date with the specific hour for the breakdown
                    if let hourDate = calendar.date(bySettingHour: entry.hour, minute: 0, second: 0, of: dayStart) {
                        hourlyAppBreakdown.append(DailyAppBreakdown(
                            date: hourDate,
                            appName: entry.appName,
                            totalSeconds: entry.totalSeconds
                        ))
                    }
                }
                
                // Create TrendPoints for all 24 hours (fill missing hours with 0)
                trend = (0..<24).compactMap { hour in
                    guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) else { return nil }
                    return TrendPoint(date: hourDate, totalSeconds: hourlyTotals[hour, default: 0])
                }
                
                dailyBreakdown = hourlyAppBreakdown
            } else {
                // Fetch daily data for Week/Month/Year views
                async let trendFetch = appEnvironment.dataService.fetchTrend(filters: snapshot)
                async let breakdownFetch = appEnvironment.dataService.fetchDailyAppBreakdown(filters: snapshot, topN: 5)

                trend = try await trendFetch
                dailyBreakdown = try await breakdownFetch
            }
        } catch {
            loadError = error
            trend = []
            dailyBreakdown = []
        }
    }
}
