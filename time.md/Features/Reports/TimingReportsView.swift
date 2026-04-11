import Charts
import SwiftUI

// MARK: - Timing-style Reports View
// Exportable time reports with date range selection, grouping, and chart visualizations.

struct TimingReportsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode

    @State private var topApps: [AppUsageSummary] = []
    @State private var topCategories: [CategoryUsageSummary] = []
    @State private var trendPoints: [TrendPoint] = []
    @State private var periodSummary: PeriodSummary?
    @State private var weekdayAverages: [WeekdayAverage] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var reportGrouping: ReportGrouping = .app
    @State private var selectedExportFormat: ExportFormat = .csv
    @State private var isExporting = false

    enum ReportGrouping: String, CaseIterable {
        case app = "By App"
        case category = "By Category"
        case day = "By Day"
    }

    private static let supportedFormats: [ExportFormat] = [.csv, .json, .markdown]

    private var totalSeconds: Double {
        periodSummary?.totalSeconds ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                reportControls

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let loadError {
                    DataLoadErrorView(error: loadError)
                } else {
                    reportSummaryCards
                    reportChart
                    reportWeekdayChart
                    reportTable
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reports")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(filters.rangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.8)
            }

            Spacer()

            // Export button
            Button {
                exportReport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Export")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
    }

    // MARK: - Report Controls

    private var reportControls: some View {
        HStack(spacing: 16) {
            Picker("Group by", selection: $reportGrouping) {
                ForEach(ReportGrouping.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            Picker("Format", selection: $selectedExportFormat) {
                ForEach(Self.supportedFormats) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }

    // MARK: - Summary Cards

    private var reportSummaryCards: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            reportStatCard(
                title: "TOTAL TIME",
                value: DurationFormatter.short(totalSeconds),
                subtitle: filters.rangeLabel,
                color: .blue
            )
            reportStatCard(
                title: "APPS TRACKED",
                value: "\(topApps.count)",
                subtitle: "\(topCategories.count) categories",
                color: .purple
            )
            reportStatCard(
                title: "TOP APP",
                value: periodSummary.map { AppNameDisplay.displayName(for: $0.topAppName, mode: appNameDisplayMode) } ?? "N/A",
                subtitle: periodSummary.map { DurationFormatter.short($0.topAppSeconds) } ?? "",
                color: .green
            )
        }
    }

    private func reportStatCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)

                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(subtitle)
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(color)
            }
        }
    }

    // MARK: - Report Chart

    private var reportChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("TIME DISTRIBUTION")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                if trendPoints.isEmpty {
                    Text("No trend data available.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    Chart(trendPoints) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Hours", point.totalSeconds / 3600)
                        )
                        .foregroundStyle(BrutalTheme.accent.opacity(0.7))
                        .cornerRadius(4)
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
                    .frame(height: 200)
                }
            }
        }
    }

    // MARK: - Weekday Chart

    private var reportWeekdayChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("WEEKDAY AVERAGES")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                if weekdayAverages.isEmpty {
                    Text("Not enough data for weekday averages.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

                    Chart(weekdayAverages) { avg in
                        BarMark(
                            x: .value("Day", weekdays[avg.weekday]),
                            y: .value("Hours", avg.averageSeconds / 3600)
                        )
                        .foregroundStyle(BrutalTheme.accent.gradient)
                        .cornerRadius(4)
                        .annotation(position: .top, alignment: .center, spacing: 4) {
                            Text(DurationFormatter.short(avg.averageSeconds))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textTertiary)
                        }
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
                    .frame(height: 180)
                }
            }
        }
    }

    // MARK: - Report Table

    private var reportTable: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("REPORT DATA")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Group {
                    switch reportGrouping {
                    case .app:
                        appReportTable
                    case .category:
                        categoryReportTable
                    case .day:
                        dayReportTable
                    }
                }
            }
        }
    }

    private var appReportTable: some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, 6)

            Rectangle()
                .fill(BrutalTheme.borderStrong)
                .frame(height: 1)

            ForEach(Array(topApps.enumerated()), id: \.element.id) { index, app in
                let pct = totalSeconds > 0 ? app.totalSeconds / totalSeconds * 100 : 0

                HStack(spacing: 0) {
                    Text(String(format: "%02d", index + 1))
                        .font(BrutalTheme.tableBody)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(width: 28, alignment: .leading)

                    #if os(macOS)
                    AppIconView(bundleID: app.appName, size: 14)
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
                .padding(.vertical, 6)

                if index < topApps.count - 1 {
                    Rectangle()
                        .fill(BrutalTheme.border)
                        .frame(height: 0.5)
                }
            }
        }
    }

    private var categoryReportTable: some View {
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
            .padding(.bottom, 6)

            Rectangle()
                .fill(BrutalTheme.borderStrong)
                .frame(height: 1)

            let catTotal = topCategories.reduce(0) { $0 + $1.totalSeconds }

            ForEach(Array(topCategories.enumerated()), id: \.element.id) { index, cat in
                let pct = catTotal > 0 ? cat.totalSeconds / catTotal * 100 : 0

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
                .padding(.vertical, 6)

                if index < topCategories.count - 1 {
                    Rectangle()
                        .fill(BrutalTheme.border)
                        .frame(height: 0.5)
                }
            }
        }
    }

    private var dayReportTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DATE")
                Spacer()
                Text("TIME")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(BrutalTheme.tableHeader)
            .foregroundColor(BrutalTheme.textTertiary)
            .tracking(0.5)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            Rectangle()
                .fill(BrutalTheme.borderStrong)
                .frame(height: 1)

            let formatter = DateFormatter()

            ForEach(Array(trendPoints.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 0) {
                    Text({
                        formatter.dateStyle = .medium
                        return formatter.string(from: point.date)
                    }())
                        .font(BrutalTheme.tableBody)
                        .foregroundColor(BrutalTheme.textPrimary)

                    Spacer()

                    Text(DurationFormatter.short(point.totalSeconds))
                        .font(BrutalTheme.tableBody)
                        .foregroundColor(BrutalTheme.textPrimary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)

                if index < trendPoints.count - 1 {
                    Rectangle()
                        .fill(BrutalTheme.border)
                        .frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - Export

    private func exportReport() {
        isExporting = true

        Task {
            defer { isExporting = false }
            let snapshot = filters.snapshot

            do {
                let url = try await appEnvironment.exportCoordinator.export(
                    format: selectedExportFormat,
                    from: .reports,
                    filters: snapshot
                )

                #if os(macOS)
                NSWorkspace.shared.open(url.deletingLastPathComponent())
                #endif
            } catch {
                // Export failed silently for now
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

            async let fetchedApps = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 50)
            async let fetchedCategories = appEnvironment.dataService.fetchTopCategories(filters: snapshot, limit: 20)
            async let fetchedTrend = appEnvironment.dataService.fetchTrend(filters: snapshot)
            async let fetchedPeriod = appEnvironment.dataService.fetchPeriodSummary(filters: snapshot)
            async let fetchedWeekday = appEnvironment.dataService.fetchWeekdayAverages(filters: snapshot)

            topApps = try await fetchedApps
            topCategories = try await fetchedCategories
            trendPoints = try await fetchedTrend
            periodSummary = try await fetchedPeriod
            weekdayAverages = try await fetchedWeekday
        } catch {
            loadError = error
        }
    }
}
