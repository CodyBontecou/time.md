import Charts
import SwiftUI

// MARK: - Session sub-page mode

private enum SessionChartMode: String, CaseIterable, Identifiable {
    case distribution = "Distribution"
    case typicalDay = "Typical Day"
    case contextSwitching = "Context Switching"

    var id: String { rawValue }
}

// MARK: - View

struct SessionsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode
    @State private var buckets: [SessionBucket] = []
    @State private var hourlyUsage: [HourlyAppUsage] = []
    @State private var contextSwitches: [ContextSwitchPoint] = []
    @State private var loadError: Error?
    @State private var hoveredBucketLabel: String?
    @State private var selectedBucketLabel: String?
    @State private var chartMode: SessionChartMode = .distribution

    // Aggregated hourly totals for "typical day"
    private var hourlyTotals: [(hour: Int, totalSeconds: Double)] {
        var dict: [Int: Double] = [:]
        for entry in hourlyUsage {
            dict[entry.hour, default: 0] += entry.totalSeconds
        }
        return (0...23).map { (hour: $0, totalSeconds: dict[$0] ?? 0) }
    }

    // Top 5 apps per hour for stacked view
    private var top5HourlyApps: [String] {
        var totals: [String: Double] = [:]
        for entry in hourlyUsage {
            totals[entry.appName, default: 0] += entry.totalSeconds
        }
        return totals.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    // Use deterministic colors from BrutalTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sessions")
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

                // Mode toggle
                HStack(spacing: 6) {
                    ForEach(SessionChartMode.allCases) { mode in
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
                    Spacer()
                }

                // Chart
                switch chartMode {
                case .distribution:
                    distributionSection
                case .typicalDay:
                    typicalDaySection
                case .contextSwitching:
                    contextSwitchingSection
                }

                // Summary stats
                summaryStats
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .task(id: filters.rangeLabel + filters.granularity.rawValue) {
            await load()
        }
    }

    // MARK: - Distribution

    private var distributionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("SESSION DURATION DISTRIBUTION")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Range", bucket.label),
                        y: .value("Sessions", bucket.sessionCount)
                    )
                    .foregroundStyle(barStyle(for: bucket))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(BrutalTheme.border)
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: buckets.map(\.sessionCount))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    updateHover(locationX: location.x, proxy: proxy, geometry: geometry)
                                case .ended:
                                    hoveredBucketLabel = nil
                                }
                            }
                            .gesture(
                                TapGesture().onEnded {
                                    if let hoveredBucketLabel {
                                        selectedBucketLabel = selectedBucketLabel == hoveredBucketLabel ? nil : hoveredBucketLabel
                                    }
                                }
                            )
                    }
                }
                .frame(height: 300)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ChartAccessibility.barChartSummary(
                    items: buckets.map { ($0.label, $0.sessionCount) }
                ))

                // Focused bucket detail
                if let focused = focusedBucket {
                    HStack(spacing: 12) {
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(focused.label)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(BrutalTheme.textPrimary)
                            Text("\(focused.sessionCount) sessions")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textSecondary)
                        }
                        Spacer()
                        if selectedBucketLabel != nil {
                            Button("Clear") {
                                selectedBucketLabel = nil
                            }
                            .buttonStyle(.glass)
                            .tint(BrutalTheme.danger)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Typical Day

    private var typicalDaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hourly total bar chart
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TYPICAL DAY — HOURLY USAGE")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    Chart(hourlyTotals, id: \.hour) { entry in
                        BarMark(
                            x: .value("Hour", hourLabel(entry.hour)),
                            y: .value("Seconds", entry.totalSeconds)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.teal.opacity(0.7), .blue.opacity(0.7)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(3)
                    }
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
                        AxisMarks(values: .stride(by: 3)) { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                }
            }

            // Stacked by-app hourly
            if !top5HourlyApps.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HOURLY BREAKDOWN — TOP 5 APPS")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)

                        let filtered = hourlyUsage.filter { top5HourlyApps.contains($0.appName) }

                        Chart(filtered) { entry in
                            BarMark(
                                x: .value("Hour", hourLabel(entry.hour)),
                                y: .value("Seconds", entry.totalSeconds)
                            )
                            .foregroundStyle(by: .value("App", AppNameDisplay.displayName(for: entry.appName, mode: appNameDisplayMode)))
                        }
                        .chartForegroundStyleScale(
                            domain: top5HourlyApps.map { AppNameDisplay.displayName(for: $0, mode: appNameDisplayMode) },
                            range: top5HourlyApps.map { BrutalTheme.color(for: $0, in: top5HourlyApps) }
                        )
                        .chartXAxis {
                            AxisMarks(values: .stride(by: 3)) { value in
                                AxisValueLabel {
                                    if let label = value.as(String.self) {
                                        Text(label)
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(BrutalTheme.textTertiary)
                                    }
                                }
                            }
                        }
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
                        .frame(height: 260)

                        // Legend
                        HStack(spacing: 16) {
                            ForEach(Array(top5HourlyApps.enumerated()), id: \.element) { idx, app in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(BrutalTheme.color(for: app, in: top5HourlyApps))
                                        .frame(width: 8, height: 8)
                                    AppNameText(app)
                                        .font(.system(size: 11, weight: .medium))
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

    // MARK: - Context Switching

    /// Aggregate context switches: total per hour across all days
    private var hourlyContextSwitches: [(hour: Int, avgSwitches: Double)] {
        var hourTotals: [Int: [Int]] = [:]
        for point in contextSwitches {
            hourTotals[point.hour, default: []].append(point.switchCount)
        }
        return (0...23).map { hour in
            let values = hourTotals[hour] ?? []
            let avg = values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
            return (hour: hour, avgSwitches: avg)
        }
    }

    private var contextSwitchingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONTEXT SWITCHES BY HOUR (AVG)")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    Text("How often you switch between apps each hour")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)

                    Chart(hourlyContextSwitches, id: \.hour) { entry in
                        BarMark(
                            x: .value("Hour", hourLabel(entry.hour)),
                            y: .value("Switches", entry.avgSwitches)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.red.opacity(0.4), .red.opacity(0.8)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(3)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                                .foregroundStyle(BrutalTheme.border)
                            AxisValueLabel {
                                if let count = value.as(Double.self) {
                                    Text(String(format: "%.0f", count))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 3)) { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                }
            }

            // Summary stats for context switching
            let totalSwitches = contextSwitches.reduce(0) { $0 + $1.switchCount }
            let peakHour = hourlyContextSwitches.max(by: { $0.avgSwitches < $1.avgSwitches })

            GlassCard {
                HStack(spacing: 24) {
                    statPill(icon: "arrow.triangle.swap", label: "Total Switches", value: "\(totalSwitches)", tint: .red)
                    if let peak = peakHour, peak.avgSwitches > 0 {
                        statPill(icon: "arrow.up", label: "Peak Hour", value: hourLabel(peak.hour), tint: .orange)
                        statPill(icon: "chart.bar.fill", label: "Peak Avg", value: String(format: "%.1f", peak.avgSwitches), tint: .purple)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Summary Stats

    private var summaryStats: some View {
        let totalSessions = buckets.reduce(0) { $0 + $1.sessionCount }

        return GlassCard {
            HStack(spacing: 24) {
                statPill(icon: "number", label: "Total Sessions", value: "\(totalSessions)", tint: .orange)
                statPill(icon: "chart.bar.fill", label: "Buckets", value: "\(buckets.count)", tint: .teal)
                if let peak = buckets.max(by: { $0.sessionCount < $1.sessionCount }) {
                    statPill(icon: "arrow.up", label: "Most Common", value: peak.label, tint: .purple)
                }
                Spacer()
            }
        }
    }

    private func statPill(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
            }
        }
    }

    // MARK: - Helpers

    private var focusedBucket: SessionBucket? {
        if let selectedBucketLabel, let b = buckets.first(where: { $0.label == selectedBucketLabel }) { return b }
        if let hoveredBucketLabel, let b = buckets.first(where: { $0.label == hoveredBucketLabel }) { return b }
        return nil
    }

    private func barStyle(for bucket: SessionBucket) -> AnyShapeStyle {
        if let selectedBucketLabel {
            return selectedBucketLabel == bucket.label
                ? AnyShapeStyle(.orange.gradient)
                : AnyShapeStyle(.gray.opacity(0.3))
        }
        if let hoveredBucketLabel {
            return hoveredBucketLabel == bucket.label
                ? AnyShapeStyle(.orange.gradient)
                : AnyShapeStyle(.orange.opacity(0.4))
        }
        return AnyShapeStyle(.orange.gradient)
    }

    private func updateHover(locationX: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { hoveredBucketLabel = nil; return }
        let plotRect = geometry[plotFrame]
        let relativeX = locationX - plotRect.origin.x
        guard relativeX >= 0, relativeX <= plotRect.width,
              let label: String = proxy.value(atX: relativeX) else { hoveredBucketLabel = nil; return }
        hoveredBucketLabel = label
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return formatter.string(from: date).lowercased()
    }

    private func load() async {
        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let bucketsFetch = appEnvironment.dataService.fetchSessionBuckets(filters: snapshot)
            async let hourlyFetch = appEnvironment.dataService.fetchHourlyAppUsage(for: Date())
            async let switchesFetch = appEnvironment.dataService.fetchContextSwitchRate(filters: snapshot)

            buckets = try await bucketsFetch
            hourlyUsage = try await hourlyFetch
            contextSwitches = try await switchesFetch
        } catch {
            loadError = error
            buckets = []
            hourlyUsage = []
            contextSwitches = []
        }
    }
}
