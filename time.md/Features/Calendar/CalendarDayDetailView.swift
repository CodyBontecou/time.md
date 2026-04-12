import Charts
import SwiftUI

struct CalendarDayDetailView: View {
    let date: Date

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode
    @State private var hourlyData: [HourlyAppUsage] = []
    @State private var loadError: Error?

    private let calendar = Calendar.current

    // MARK: - Computed

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date).uppercased()
    }

    private var hourlyTotals: [HourTotal] {
        var byHour: [Int: Double] = [:]
        for entry in hourlyData {
            byHour[entry.hour, default: 0] += entry.totalSeconds
        }
        return (0..<24).map { hour in
            HourTotal(hour: hour, totalSeconds: byHour[hour] ?? 0)
        }
    }

    private var topApps: [AppDaySummary] {
        var byApp: [String: Double] = [:]
        for entry in hourlyData {
            byApp[entry.appName, default: 0] += entry.totalSeconds
        }
        return byApp
            .map { AppDaySummary(appName: $0.key, totalSeconds: $0.value) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private var totalDaySeconds: Double {
        hourlyData.reduce(0) { $0 + $1.totalSeconds }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: dateTitle)
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .tracking(1)

                Text("TOTAL: \(DurationFormatter.short(totalDaySeconds))")
                    .font(BrutalTheme.metricSmall)
                    .foregroundColor(BrutalTheme.accent)
            }

            Rectangle()
                .fill(BrutalTheme.borderStrong)
                .frame(height: 1)

            if let loadError {
                DataLoadErrorView(error: loadError)
            }

            if hourlyData.isEmpty && loadError == nil {
                GlassCard {
                    Text("NO SCREEN TIME RECORDED.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                hourlyTimelineChart
                hourlyDetailGrid
                topAppsSection
            }
        }
        .task(id: calendar.startOfDay(for: date)) {
            await load()
        }
    }

    // MARK: - Hourly timeline chart

    private var hourlyTimelineChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(1, "HOURLY ACTIVITY"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Chart(hourlyTotals) { entry in
                    BarMark(
                        x: .value("Hour", entry.hourLabel),
                        y: .value("Minutes", entry.totalSeconds / 60)
                    )
                    .foregroundStyle(BrutalTheme.accent)
                    .cornerRadius(0)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(BrutalTheme.border)
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(DurationFormatter.short(minutes * 60))
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 3)) { _ in
                        AxisValueLabel()
                            .font(BrutalTheme.captionMono)
                    }
                }
                .frame(height: 200)
            }
        }
    }

    // MARK: - Hourly detail grid

    private var hourlyDetailGrid: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(2, "BREAKDOWN"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                let activeHours = hourlyTotals.filter { $0.totalSeconds > 0 }

                if activeHours.isEmpty {
                    Text("NO ACTIVITY RECORDED.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(activeHours) { hourTotal in
                            let appsThisHour = hourlyData
                                .filter { $0.hour == hourTotal.hour }
                                .sorted { $0.totalSeconds > $1.totalSeconds }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(hourTotal.hourLabel.uppercased())
                                        .font(BrutalTheme.tableBody)
                                        .fontWeight(.bold)
                                        .frame(width: 50, alignment: .leading)

                                    // Proportion bar — sharp
                                    GeometryReader { geo in
                                        let fraction = min(hourTotal.totalSeconds / 3600, 1)
                                        Rectangle()
                                            .fill(BrutalTheme.accent.opacity(0.25))
                                            .frame(width: geo.size.width * fraction)
                                    }
                                    .frame(height: 6)

                                    Text(DurationFormatter.short(hourTotal.totalSeconds))
                                        .font(BrutalTheme.tableBody)
                                        .foregroundColor(BrutalTheme.textTertiary)
                                        .frame(width: 60, alignment: .trailing)
                                }

                                // Top apps for this hour
                                HStack(spacing: 12) {
                                    ForEach(appsThisHour.prefix(3), id: \.appName) { app in
                                        HStack(spacing: 4) {
                                            Rectangle()
                                                .fill(BrutalTheme.accent)
                                                .frame(width: 4, height: 4)
                                            AppNameText(app.appName)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Text(DurationFormatter.short(app.totalSeconds))
                                                .foregroundColor(BrutalTheme.textTertiary)
                                        }
                                        .font(BrutalTheme.captionMono)
                                    }
                                }
                                .padding(.leading, 50)
                            }
                            .padding(.vertical, 8)

                            if hourTotal.hour != activeHours.last?.hour {
                                Rectangle()
                                    .fill(BrutalTheme.border)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Top apps section

    private var topAppsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("APP USAGE")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                if topApps.isEmpty {
                    Text("NO APP DATA.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    // Horizontal bar chart
                    let display = Array(topApps.prefix(10))

                    Chart(display) { app in
                        BarMark(
                            x: .value("Time", app.totalSeconds / 60),
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
                                    Text(verbatim: name)
                                        .font(BrutalTheme.captionMono)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: max(CGFloat(display.count) * 36, 100))

                    Rectangle()
                        .fill(BrutalTheme.borderStrong)
                        .frame(height: 1)

                    // Detailed table
                    VStack(spacing: 0) {
                        HStack {
                            Text("#")
                                .frame(width: 28, alignment: .leading)
                            Text("APP")
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

                        ForEach(Array(topApps.enumerated()), id: \.element.appName) { index, app in
                            let pct = totalDaySeconds > 0 ? app.totalSeconds / totalDaySeconds * 100 : 0

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

                                    Text(String(format: "%.1f%%", pct))
                                        .font(BrutalTheme.tableBody)
                                        .foregroundColor(BrutalTheme.textTertiary)
                                        .frame(width: 48, alignment: .trailing)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)

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
            }
        }
    }

    // MARK: - Data loading

    private func load() async {
        do {
            loadError = nil
            hourlyData = try await appEnvironment.dataService.fetchHourlyAppUsage(for: date)
        } catch {
            loadError = error
            hourlyData = []
        }
    }
}

// MARK: - Local models

private struct HourTotal: Identifiable {
    let hour: Int
    let totalSeconds: Double

    var id: Int { hour }

    var hourLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date).lowercased()
        }
        return "\(hour):00"
    }
}

private struct AppDaySummary: Identifiable {
    var id: String { appName }
    let appName: String
    let totalSeconds: Double
}
