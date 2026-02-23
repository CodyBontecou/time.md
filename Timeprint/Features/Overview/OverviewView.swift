import Charts
import SwiftUI

// MARK: - Chart mode

enum OverviewChartMode: String, CaseIterable, Identifiable {
    case calendar = "Calendar"
    case topApps = "Top Apps"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .calendar: return "calendar"
        case .topApps: return "chart.bar.fill"
        }
    }
}

// MARK: - View

struct OverviewView: View {
    let filters: GlobalFilterStore
    @Binding var isCalendarExpanded: Bool

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode
    @State private var summary = DashboardSummary(totalSeconds: 0, averageDailySeconds: 0, focusBlocks: 0, currentStreakDays: 0)
    @State private var topApps: [AppUsageSummary] = []
    @State private var loadError: Error?
    @State private var chartMode: OverviewChartMode = .calendar
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false

    // MARK: Computed helpers

    private var averageLabel: String { "AVG / DAY" }

    private var chartTitle: String {
        switch chartMode {
        case .calendar: return "CALENDAR"
        case .topApps: return "TOP APPS"
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ─── Header Row: Title + Date | Granularity Picker ───
                headerSection

                // ─── Metrics Strip ───
                metricsStrip

                if let loadError {
                    DataLoadErrorView(error: loadError)
                }

                // ─── Content Area with integrated mode picker ───
                contentSection
            }
        }
        .task(id: filters.rangeLabel + filters.granularity.rawValue) {
            await load()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center) {
            // Left: Title + date
            VStack(alignment: .leading, spacing: 4) {
                Text("Overview")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(filters.rangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.8)
            }

            Spacer(minLength: 20)

            // Right: Granularity segmented control
            granularityPicker
        }
    }

    // MARK: - Granularity Picker (pill-style segmented control)

    private var granularityPicker: some View {
        HStack(spacing: 2) {
            ForEach(TimeGranularity.allCases) { granularity in
                let isActive = filters.granularity == granularity

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filters.granularity = granularity
                    }
                } label: {
                    Text(granularity.title)
                        .font(.system(size: 12, weight: isActive ? .bold : .medium, design: .monospaced))
                        .foregroundColor(isActive ? .white : BrutalTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isActive ? BrutalTheme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.04))
        )
    }

    // MARK: - Metrics Strip

    private var metricsStrip: some View {
        HStack(spacing: 12) {
            metricPill(
                icon: "clock.fill",
                label: "Total",
                value: DurationFormatter.short(summary.totalSeconds)
            )
            metricPill(
                icon: "chart.line.uptrend.xyaxis",
                label: "Daily Avg",
                value: DurationFormatter.short(summary.averageDailySeconds)
            )
            metricPill(
                icon: "target",
                label: "Focus Blocks",
                value: "\(summary.focusBlocks)"
            )
            metricPill(
                icon: "flame.fill",
                label: "Streak",
                value: "\(summary.currentStreakDays)d"
            )
        }
    }

    private func metricPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BrutalTheme.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(BrutalTheme.accentMuted)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(BrutalTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Content Section (chart mode picker + chart)

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header with integrated mode toggle
            HStack(alignment: .center) {
                // Mode toggle (left-aligned, integrated)
                HStack(spacing: 0) {
                    ForEach(OverviewChartMode.allCases) { mode in
                        let isActive = chartMode == mode

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                chartMode = mode
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(mode.rawValue)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(isActive ? BrutalTheme.accent : BrutalTheme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isActive ? BrutalTheme.accentMuted : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }

            // Chart content
            if chartMode == .calendar && !isCalendarExpanded {
                AppleCalendarView(filters: filters, isExpanded: $isCalendarExpanded)
                    .frame(minHeight: 520)
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(chartTitle)
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)

                        topAppsChart
                    }
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
            .cornerRadius(0)
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
                        Rectangle()
                            .fill(BrutalTheme.accentMuted)
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
                .background(BrutalTheme.surface)
                .overlay(
                    Rectangle()
                        .strokeBorder(BrutalTheme.border, lineWidth: BrutalTheme.borderWidth)
                )
            }
            .buttonStyle(.plain)
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
                .background(BrutalTheme.surface)
                .overlay(
                    Rectangle()
                        .strokeBorder(BrutalTheme.border, lineWidth: BrutalTheme.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showEndDatePicker) {
                DatePicker("To", selection: $bindableFilters.endDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
            }
        }
    }

    // MARK: - Data loading

    private func load() async {
        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let fetchedSummary = appEnvironment.dataService.fetchDashboardSummary(filters: snapshot)
            async let fetchedApps = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 30)

            summary = try await fetchedSummary
            topApps = try await fetchedApps
        } catch {
            loadError = error
            summary = DashboardSummary(totalSeconds: 0, averageDailySeconds: 0, focusBlocks: 0, currentStreakDays: 0)
            topApps = []
        }
    }
}
