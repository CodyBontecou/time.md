import Charts
import SwiftUI

// MARK: - Focus score tiers

private enum FocusScore: String {
    case great = "Great"
    case moderate = "Moderate"
    case high = "High"

    var color: Color {
        switch self {
        case .great: .green
        case .moderate: .orange
        case .high: .red
        }
    }

    var icon: String {
        switch self {
        case .great: "checkmark.seal.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .high: "flame.fill"
        }
    }

    static func from(seconds: Double) -> FocusScore {
        let hours = seconds / 3600
        if hours < 4 { return .great }
        if hours < 6 { return .moderate }
        return .high
    }
}

// MARK: - View

struct FocusStreaksView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var focusDays: [FocusDay] = []
    @State private var loadError: Error?

    // Streak calculations
    private var currentStreak: Int {
        focusDays.sorted { $0.date > $1.date }.prefix { $0.focusBlocks > 0 }.count
    }

    private var longestStreak: Int {
        var maxRun = 0, run = 0
        for day in focusDays.sorted(by: { $0.date < $1.date }) {
            if day.focusBlocks > 0 { run += 1; maxRun = max(maxRun, run) }
            else { run = 0 }
        }
        return maxRun
    }

    private var todayScore: FocusScore {
        let today = Calendar.current.startOfDay(for: .now)
        let todaySeconds = focusDays.first { Calendar.current.isDate($0.date, inSameDayAs: today) }?.totalSeconds ?? 0
        return .from(seconds: todaySeconds)
    }

    // Weekly aggregations for summary cards
    private var weeklySummaries: [(weekStart: Date, totalSeconds: Double, avgDaily: Double, days: Int)] {
        let calendar = Calendar.current
        var grouped: [Date: [FocusDay]] = [:]
        for day in focusDays {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: day.date)?.start ?? day.date
            grouped[weekStart, default: []].append(day)
        }
        return grouped.sorted { $0.key > $1.key }.prefix(4).map { weekStart, days in
            let total = days.reduce(0.0) { $0 + $1.totalSeconds }
            return (weekStart, total, total / max(Double(days.count), 1), days.count)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focus & Streaks")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(BrutalTheme.textPrimary)
                        Text("YOUR CONSISTENCY AT A GLANCE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .tracking(0.8)
                    }
                    Spacer()
                }

                if let loadError {
                    DataLoadErrorView(error: loadError)
                }

                // Streak + Score cards
                streakCardsRow

                // Contribution calendar
                contributionCalendar

                // Focus blocks chart
                focusBlocksChart

                // Weekly summaries
                weeklySummaryCards

                // Score legend
                scoreLegend
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .task(id: filters.rangeLabel + filters.granularity.rawValue) {
            await load()
        }
    }

    // MARK: - Streak Cards

    private var streakCardsRow: some View {
        HStack(spacing: 12) {
                // Current streak
                streakCard(
                    icon: "flame.fill",
                    label: "CURRENT STREAK",
                    value: "\(currentStreak)",
                    unit: currentStreak == 1 ? "day" : "days",
                    tint: .orange
                )

                // Longest streak
                streakCard(
                    icon: "trophy.fill",
                    label: "LONGEST STREAK",
                    value: "\(longestStreak)",
                    unit: longestStreak == 1 ? "day" : "days",
                    tint: .yellow
                )

                // Today's score
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: todayScore.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(todayScore.color)
                        Text("TODAY'S FOCUS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .tracking(1)
                    }
                    Text(todayScore.rawValue)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(todayScore.color)

                    let todaySeconds = focusDays.first { Calendar.current.isDate($0.date, inSameDayAs: .now) }?.totalSeconds ?? 0
                    Text(DurationFormatter.short(todaySeconds))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                

                // Total focus blocks
                streakCard(
                    icon: "target",
                    label: "FOCUS BLOCKS",
                    value: "\(focusDays.reduce(0) { $0 + $1.focusBlocks })",
                    unit: "total",
                    tint: .purple
                )
        }
    }

    private func streakCard(icon: String, label: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let num = Double(value) {
                    AnimatedNumber(num, font: .system(size: 28, weight: .heavy, design: .rounded))
                } else {
                    Text(value)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(BrutalTheme.textPrimary)
                }
                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }

    // MARK: - Contribution Calendar (GitHub-style)

    private var contributionCalendar: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVITY CALENDAR")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                let calendar = Calendar.current
                let dayLabels = ["", "Mon", "", "Wed", "", "Fri", ""]
                let sortedDays = focusDays.sorted { $0.date < $1.date }
                let maxFocusBlocks = max(sortedDays.map(\.focusBlocks).max() ?? 1, 1)

                // Build a map of date -> focusDay
                let dayMap: [Date: FocusDay] = Dictionary(
                    sortedDays.map { (calendar.startOfDay(for: $0.date), $0) },
                    uniquingKeysWith: { a, _ in a }
                )

                // Calculate weeks
                let endDate = calendar.startOfDay(for: filters.endDate)
                let startDate = calendar.startOfDay(for: filters.startDate)
                let totalDays = max(calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0, 1)
                let totalWeeks = (totalDays + 6) / 7

                HStack(alignment: .top, spacing: 2) {
                    // Day-of-week labels
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { day in
                            Text(dayLabels[day])
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textTertiary)
                                .frame(width: 24, height: 12)
                        }
                    }

                    // Weeks grid
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(0..<totalWeeks, id: \.self) { week in
                                VStack(spacing: 2) {
                                    ForEach(0..<7, id: \.self) { dayOfWeek in
                                        let dayOffset = week * 7 + dayOfWeek
                                        let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate

                                        if date <= endDate {
                                            let day = dayMap[calendar.startOfDay(for: date)]
                                            let intensity = day.map { Double($0.focusBlocks) / Double(maxFocusBlocks) } ?? 0

                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(contributionColor(intensity: intensity))
                                                .frame(width: 12, height: 12)
                                                .help("\(shortDateLabel(date)) — \(day?.focusBlocks ?? 0) blocks")
                                        } else {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.clear)
                                                .frame(width: 12, height: 12)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func contributionColor(intensity: Double) -> Color {
        if intensity <= 0 {
            return BrutalTheme.border
        }
        return BrutalTheme.heatmapColor(intensity: intensity)
    }

    // MARK: - Focus Blocks Chart

    private var focusBlocksChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("DAILY FOCUS BLOCKS")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Chart(focusDays.sorted(by: { $0.date < $1.date })) { day in
                    BarMark(
                        x: .value("Date", day.date),
                        y: .value("Blocks", day.focusBlocks)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.purple.opacity(0.5), .purple],
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
                            if let date = value.as(Date.self) {
                                Text(shortDateLabel(date))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
    }

    // MARK: - Weekly Summary Cards

    private var weeklySummaryCards: some View {
        Group {
            if !weeklySummaries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WEEKLY SUMMARIES")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    HStack(spacing: 12) {
                        ForEach(weeklySummaries, id: \.weekStart) { week in
                                let score = FocusScore.from(seconds: week.avgDaily)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Week of \(shortDateLabel(week.weekStart))")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                        .tracking(0.5)

                                    Text(DurationFormatter.short(week.totalSeconds))
                                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                                        .foregroundColor(BrutalTheme.textPrimary)

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(score.color)
                                            .frame(width: 6, height: 6)
                                        Text("\(DurationFormatter.short(week.avgDaily))/day avg")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(BrutalTheme.textSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                
                        }
                    }
                }
            }
        }
    }

    // MARK: - Score Legend

    private var scoreLegend: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("FOCUS SCORE GUIDE")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                HStack(spacing: 24) {
                    legendItem(score: .great, description: "< 4h screen time")
                    legendItem(score: .moderate, description: "4–6h screen time")
                    legendItem(score: .high, description: "> 6h screen time")
                }
            }
        }
    }

    private func legendItem(score: FocusScore, description: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: score.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(score.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(score.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(BrutalTheme.textPrimary)
                Text(description)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func load() async {
        do {
            loadError = nil
            focusDays = try await appEnvironment.dataService.fetchFocusDays(filters: filters.snapshot)
        } catch {
            loadError = error
            focusDays = []
        }
    }
}
