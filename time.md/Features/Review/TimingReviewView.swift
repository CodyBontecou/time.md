import Charts
import SwiftUI

// MARK: - Timing-style Review View
// Detailed breakdown of tracked time with charts, filterable lists, and drill-down.

struct TimingReviewView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode

    @State private var topApps: [AppUsageSummary] = []
    @State private var topCategories: [CategoryUsageSummary] = []
    @State private var trendPoints: [TrendPoint] = []
    @State private var dailyBreakdown: [DailyAppBreakdown] = []
    @State private var heatmapCells: [HeatmapCell] = []
    @State private var periodSummary: PeriodSummary?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var groupBy: GroupByMode = .app
    @State private var chartMode: ChartMode = .bar

    enum GroupByMode: String, CaseIterable {
        case app = "Apps"
        case category = "Categories"
    }

    enum ChartMode: String, CaseIterable {
        case bar = "Bar"
        case pie = "Pie"
        case trend = "Trend"
    }

    private var totalSeconds: Double {
        periodSummary?.totalSeconds ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                controlBar

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let loadError {
                    DataLoadErrorView(error: loadError)
                } else {
                    chartSection
                    heatmapSection
                    detailTable
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Review")
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundColor(BrutalTheme.textPrimary)

            HStack(spacing: 8) {
                Text(filters.rangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.8)

                if totalSeconds > 0 {
                    Text("--")
                        .foregroundColor(BrutalTheme.textTertiary)
                    Text(DurationFormatter.short(totalSeconds))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.accent)
                }
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 16) {
            // Group by picker
            Picker("Group by", selection: $groupBy) {
                ForEach(GroupByMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            // Chart mode picker
            Picker("Chart", selection: $chartMode) {
                ForEach(ChartMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()
        }
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(chartMode == .trend ? "TIME TREND" : "\(groupBy.rawValue.uppercased()) BREAKDOWN")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Group {
                    switch chartMode {
                    case .bar:
                        barChart
                    case .pie:
                        pieChart
                    case .trend:
                        trendChart
                    }
                }
                .frame(minHeight: 250)
            }
        }
    }

    private var barChart: some View {
        Group {
            if groupBy == .app {
                let display = Array(topApps.prefix(10))
                Chart(display) { app in
                    BarMark(
                        x: .value("Hours", app.totalSeconds / 3600),
                        y: .value("App", AppNameDisplay.displayName(for: app.appName, mode: appNameDisplayMode))
                    )
                    .foregroundStyle(BrutalTheme.color(for: app.appName))
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
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: max(CGFloat(display.count) * 36, 100))
            } else {
                let display = Array(topCategories.prefix(10))
                Chart(display) { cat in
                    BarMark(
                        x: .value("Hours", cat.totalSeconds / 3600),
                        y: .value("Category", cat.category)
                    )
                    .foregroundStyle(BrutalTheme.color(for: cat.category))
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                        Text(DurationFormatter.short(cat.totalSeconds))
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
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: max(CGFloat(display.count) * 36, 100))
            }
        }
    }

    private var pieChart: some View {
        Group {
            if groupBy == .app {
                let display = Array(topApps.prefix(8))
                let otherSeconds = topApps.dropFirst(8).reduce(0) { $0 + $1.totalSeconds }

                HStack(spacing: 24) {
                    Chart {
                        ForEach(display) { app in
                            SectorMark(
                                angle: .value("Time", app.totalSeconds),
                                innerRadius: .ratio(0.5),
                                angularInset: 1
                            )
                            .foregroundStyle(BrutalTheme.color(for: app.appName))
                        }
                        if otherSeconds > 0 {
                            SectorMark(
                                angle: .value("Time", otherSeconds),
                                innerRadius: .ratio(0.5),
                                angularInset: 1
                            )
                            .foregroundStyle(BrutalTheme.appColorOther)
                        }
                    }
                    .frame(width: 200, height: 200)

                    pieLegend(items: display.map { ($0.appName, $0.totalSeconds) },
                              otherSeconds: otherSeconds)
                }
                .frame(maxWidth: .infinity)
            } else {
                let display = Array(topCategories.prefix(8))
                let otherSeconds = topCategories.dropFirst(8).reduce(0) { $0 + $1.totalSeconds }

                HStack(spacing: 24) {
                    Chart {
                        ForEach(display) { cat in
                            SectorMark(
                                angle: .value("Time", cat.totalSeconds),
                                innerRadius: .ratio(0.5),
                                angularInset: 1
                            )
                            .foregroundStyle(BrutalTheme.color(for: cat.category))
                        }
                        if otherSeconds > 0 {
                            SectorMark(
                                angle: .value("Time", otherSeconds),
                                innerRadius: .ratio(0.5),
                                angularInset: 1
                            )
                            .foregroundStyle(BrutalTheme.appColorOther)
                        }
                    }
                    .frame(width: 200, height: 200)

                    pieLegend(items: display.map { ($0.category, $0.totalSeconds) },
                              otherSeconds: otherSeconds)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func pieLegend(items: [(String, Double)], otherSeconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { name, seconds in
                HStack(spacing: 6) {
                    Circle()
                        .fill(BrutalTheme.color(for: name))
                        .frame(width: 8, height: 8)
                    Text(AppNameDisplay.displayName(for: name, mode: appNameDisplayMode))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(DurationFormatter.short(seconds))
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textSecondary)
                }
            }
            if otherSeconds > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BrutalTheme.appColorOther)
                        .frame(width: 8, height: 8)
                    Text("Other")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Spacer()
                    Text(DurationFormatter.short(otherSeconds))
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: 200)
    }

    private var trendChart: some View {
        Chart(trendPoints) { point in
            AreaMark(
                x: .value("Date", point.date),
                y: .value("Hours", point.totalSeconds / 3600)
            )
            .foregroundStyle(BrutalTheme.accent.opacity(0.15))

            LineMark(
                x: .value("Date", point.date),
                y: .value("Hours", point.totalSeconds / 3600)
            )
            .foregroundStyle(BrutalTheme.accent)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(String(format: "%.0fh", hours))
                            .font(BrutalTheme.captionMono)
                    }
                }
            }
        }
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVITY HEATMAP")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                let maxSeconds = heatmapCells.map(\.totalSeconds).max() ?? 1
                let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

                VStack(spacing: 2) {
                    // Hour labels
                    HStack(spacing: 2) {
                        Text("")
                            .frame(width: 32)
                        ForEach(0..<24, id: \.self) { hour in
                            if hour % 4 == 0 {
                                Text(formatHourShort(hour))
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(height: 12)

                    // Grid
                    ForEach(0..<7, id: \.self) { weekday in
                        HStack(spacing: 2) {
                            Text(weekdays[weekday])
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textTertiary)
                                .frame(width: 32, alignment: .trailing)

                            ForEach(0..<24, id: \.self) { hour in
                                let cell = heatmapCells.first { $0.weekday == weekday && $0.hour == hour }
                                let intensity = (cell?.totalSeconds ?? 0) / maxSeconds

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(BrutalTheme.heatmapColor(intensity: intensity))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1.0, contentMode: .fit)
                                    .help(cell.map { "\(weekdays[$0.weekday]) \(formatHourShort($0.hour)): \(DurationFormatter.short($0.totalSeconds))" } ?? "No data")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detail Table

    private var detailTable: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("DETAILED BREAKDOWN")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                if groupBy == .app {
                    appDetailTable
                } else {
                    categoryDetailTable
                }
            }
        }
    }

    private var appDetailTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("#")
                    .frame(width: 28, alignment: .leading)
                Text("APP")
                Spacer()
                Text("TIME")
                    .frame(width: 80, alignment: .trailing)
                Text("SESSIONS")
                    .frame(width: 70, alignment: .trailing)
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

            ForEach(Array(topApps.enumerated()), id: \.element.id) { index, app in
                let pct = totalSeconds > 0 ? app.totalSeconds / totalSeconds * 100 : 0

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(String(format: "%02d", index + 1))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 28, alignment: .leading)

                        Circle()
                            .fill(BrutalTheme.color(for: app.appName))
                            .frame(width: 8, height: 8)
                            .padding(.trailing, 6)

                        #if os(macOS)
                        AppIconView(bundleID: app.appName, size: 16)
                        #endif

                        AppNameText(app.appName)
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(DurationFormatter.short(app.totalSeconds))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .frame(width: 80, alignment: .trailing)

                        Text("\(app.sessionCount)")
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 70, alignment: .trailing)

                        Text(String(format: "%.1f%%", pct))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BrutalTheme.color(for: app.appName).opacity(0.25))
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

    private var categoryDetailTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("#")
                    .frame(width: 28, alignment: .leading)
                Text("CATEGORY")
                Spacer()
                Text("TIME")
                    .frame(width: 80, alignment: .trailing)
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

            let catTotal = topCategories.reduce(0) { $0 + $1.totalSeconds }

            ForEach(Array(topCategories.enumerated()), id: \.element.id) { index, cat in
                let pct = catTotal > 0 ? cat.totalSeconds / catTotal * 100 : 0

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text(String(format: "%02d", index + 1))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 28, alignment: .leading)

                        Circle()
                            .fill(BrutalTheme.color(for: cat.category))
                            .frame(width: 8, height: 8)
                            .padding(.trailing, 6)

                        Text(cat.category)
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(DurationFormatter.short(cat.totalSeconds))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .frame(width: 80, alignment: .trailing)

                        Text(String(format: "%.1f%%", pct))
                            .font(BrutalTheme.tableBody)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BrutalTheme.color(for: cat.category).opacity(0.25))
                            .frame(width: geo.size.width * max(pct / 100, 0), height: 3)
                    }
                    .frame(height: 3)

                    if index < topCategories.count - 1 {
                        Rectangle()
                            .fill(BrutalTheme.border)
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let fetchedApps = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 30)
            async let fetchedCategories = appEnvironment.dataService.fetchTopCategories(filters: snapshot, limit: 20)
            async let fetchedTrend = appEnvironment.dataService.fetchTrend(filters: snapshot)
            async let fetchedHeatmap = appEnvironment.dataService.fetchHeatmap(filters: snapshot)
            async let fetchedPeriod = appEnvironment.dataService.fetchPeriodSummary(filters: snapshot)
            async let fetchedDaily = appEnvironment.dataService.fetchDailyAppBreakdown(filters: snapshot, topN: 5)

            topApps = try await fetchedApps
            topCategories = try await fetchedCategories
            trendPoints = try await fetchedTrend
            heatmapCells = try await fetchedHeatmap
            periodSummary = try await fetchedPeriod
            dailyBreakdown = try await fetchedDaily
        } catch {
            loadError = error
        }
    }

    private func formatHourShort(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }
}
