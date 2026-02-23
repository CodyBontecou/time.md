import SwiftUI

/// Google Calendar-inspired two-panel layout — month grid on the left,
/// day detail sidebar on the right. Everything fits in a single view
/// with no vertical scrolling required.
struct CalendarAnalysisView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var displayedMonth: Date = .now
    @State private var dailyTotals: [Date: Double] = [:]
    @State private var selectedDay: Date?
    @State private var loadError: Error?

    // Day detail state
    @State private var dayHourlyData: [HourlyAppUsage] = []
    @State private var dayLoadError: Error?

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    // MARK: - Computed (Month)

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth).uppercased()
    }

    private var monthInterval: DateInterval? {
        calendar.dateInterval(of: .month, for: displayedMonth)
    }

    private var calendarDays: [Date?] {
        guard let interval = monthInterval else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = firstWeekday - calendar.firstWeekday
        let adjustedBlanks = leadingBlanks < 0 ? leadingBlanks + 7 : leadingBlanks

        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: adjustedBlanks)
        for dayOffset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: interval.start) {
                days.append(date)
            }
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private var maxDailySeconds: Double {
        dailyTotals.values.max() ?? 1
    }

    // MARK: - Computed (Day Detail)

    private var dayHourlyTotals: [PanelHourTotal] {
        var byHour: [Int: Double] = [:]
        for entry in dayHourlyData {
            byHour[entry.hour, default: 0] += entry.totalSeconds
        }
        return (0..<24).map { hour in
            PanelHourTotal(hour: hour, totalSeconds: byHour[hour] ?? 0)
        }
    }

    private var dayTopApps: [PanelAppSummary] {
        var byApp: [String: Double] = [:]
        for entry in dayHourlyData {
            byApp[entry.appName, default: 0] += entry.totalSeconds
        }
        return byApp
            .map { PanelAppSummary(appName: $0.key, totalSeconds: $0.value) }
            .sorted {
                if $0.totalSeconds != $1.totalSeconds { return $0.totalSeconds > $1.totalSeconds }
                return $0.appName < $1.appName
            }
    }

    private var dayTotalSeconds: Double {
        dayHourlyData.reduce(0) { $0 + $1.totalSeconds }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let loadError {
                DataLoadErrorView(error: loadError)
                    .padding(.bottom, 8)
            }

            HStack(alignment: .top, spacing: 0) {
                // ─── Left: Calendar Grid ───
                calendarGridPanel

                // ─── Vertical divider ───
                Rectangle()
                    .fill(BrutalTheme.border)
                    .frame(width: 1)

                // ─── Right: Detail Panel ───
                detailPanel
                    .frame(width: 300)
            }
            .background(BrutalTheme.surface)
            .overlay(
                Rectangle()
                    .strokeBorder(BrutalTheme.border, lineWidth: BrutalTheme.borderWidth)
            )
        }
        .task(id: monthTaskID) {
            await loadMonth()
        }
        .task(id: selectedDayTaskID) {
            await loadDayDetail()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Calendar Grid Panel (Left)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var calendarGridPanel: some View {
        VStack(spacing: 0) {
            // Month navigation header
            monthHeader

            Rectangle().fill(BrutalTheme.border).frame(height: 0.5)

            // Weekday labels
            weekdayRow

            Rectangle().fill(BrutalTheme.border).frame(height: 0.5)

            // Day cells grid
            dayGrid

            Rectangle().fill(BrutalTheme.border).frame(height: 0.5)

            // Bottom strip: legend + month summary
            bottomStrip
        }
    }

    // MARK: Month Header

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button { navigateMonth(by: -1) } label: {
                Text("←")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(monthTitle)
                .font(BrutalTheme.headingFont)
                .foregroundColor(BrutalTheme.textPrimary)
                .tracking(2)

            if !calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = .now
                        selectedDay = nil
                    }
                } label: {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BrutalTheme.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button { navigateMonth(by: 1) } label: {
                Text("→")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Weekday Row

    private var weekdayRow: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 0
        ) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .background(BrutalTheme.surfaceAlt)
    }

    // MARK: Day Grid

    private var dayGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 0
        ) {
            ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                if let date {
                    compactDayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 48)
                        .overlay(
                            Rectangle()
                                .strokeBorder(BrutalTheme.border.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    // MARK: Compact Day Cell

    private func compactDayCell(for date: Date) -> some View {
        let dayNumber = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isFuture = date > Date.now
        let totalSeconds = dailyTotals[calendar.startOfDay(for: date)] ?? 0
        let fraction = maxDailySeconds > 0 ? totalSeconds / maxDailySeconds : 0

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedDay = nil
                } else {
                    selectedDay = date
                }
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if isToday {
                        Circle()
                            .fill(BrutalTheme.accent)
                            .frame(width: 22, height: 22)
                    }

                    Text("\(dayNumber)")
                        .font(.system(size: 11, weight: isToday ? .bold : .regular, design: .monospaced))
                        .foregroundColor(
                            isToday ? .white
                                : isFuture ? BrutalTheme.textTertiary
                                : BrutalTheme.textPrimary
                        )
                }

                if totalSeconds > 0 {
                    Text(DurationFormatter.short(totalSeconds))
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    // Reserve space so cells align
                    Text(" ")
                        .font(.system(size: 7, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                totalSeconds > 0
                    ? intensityColor(fraction: fraction).opacity(0.25)
                    : Color.clear
            )
            .overlay(
                Rectangle()
                    .strokeBorder(
                        isSelected ? BrutalTheme.accent : BrutalTheme.border.opacity(0.15),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom Strip

    private var bottomStrip: some View {
        let totals = Array(dailyTotals.values)
        let totalSeconds = totals.reduce(0, +)
        let activeDays = totals.filter { $0 > 0 }.count
        let avgSeconds = activeDays > 0 ? totalSeconds / Double(activeDays) : 0

        return HStack(spacing: 16) {
            // Intensity legend
            HStack(spacing: 0) {
                Text("LESS")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.trailing, 4)

                ForEach(0..<5) { level in
                    Rectangle()
                        .fill(intensityColor(fraction: Double(level) / 4.0))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Rectangle()
                                .strokeBorder(BrutalTheme.border, lineWidth: 0.5)
                        )
                }

                Text("MORE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.leading, 4)
            }

            Spacer()

            // Month stats
            if !dailyTotals.isEmpty {
                HStack(spacing: 14) {
                    inlineStat(label: "TOTAL", value: DurationFormatter.short(totalSeconds))
                    inlineStat(label: "AVG", value: DurationFormatter.short(avgSeconds))
                    inlineStat(label: "ACTIVE", value: "\(activeDays)D")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BrutalTheme.surfaceAlt)
    }

    private func inlineStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Detail Panel (Right)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedDay {
            dayDetailContent(for: selectedDay)
        } else {
            emptyStatePanel
        }
    }

    // MARK: Empty State

    private var emptyStatePanel: some View {
        let totals = Array(dailyTotals.values)
        let totalSeconds = totals.reduce(0, +)
        let activeDays = totals.filter { $0 > 0 }.count
        let avgSeconds = activeDays > 0 ? totalSeconds / Double(activeDays) : 0
        let peakDay = dailyTotals.max(by: { $0.value < $1.value })

        return VStack(spacing: 0) {
            // Month overview header
            VStack(alignment: .leading, spacing: 4) {
                Text("MONTH OVERVIEW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle().fill(BrutalTheme.border).frame(height: 0.5)
                .padding(.horizontal, 14)

            if dailyTotals.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(BrutalTheme.textTertiary.opacity(0.5))

                    Text("NO DATA YET")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .tracking(0.5)
                }
                Spacer()
            } else {
                // Stats grid
                VStack(spacing: 0) {
                    panelMetric(label: "TOTAL SCREEN TIME", value: DurationFormatter.short(totalSeconds))
                    panelMetric(label: "DAILY AVERAGE", value: DurationFormatter.short(avgSeconds))
                    panelMetric(label: "ACTIVE DAYS", value: "\(activeDays) OF \(calendarDays.compactMap({ $0 }).count)")

                    if let peakDay {
                        let formatter: DateFormatter = {
                            let f = DateFormatter()
                            f.dateFormat = "MMM d"
                            return f
                        }()
                        panelMetric(
                            label: "PEAK DAY",
                            value: "\(formatter.string(from: peakDay.key).uppercased()) — \(DurationFormatter.short(peakDay.value))"
                        )
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 16)

                // Prompt
                VStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(BrutalTheme.textTertiary.opacity(0.4))
                    Text("SELECT A DAY FOR DETAILS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary.opacity(0.5))
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
        }
    }

    private func panelMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Day Detail Content

    private func dayDetailContent(for date: Date) -> some View {
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMM d"
            return f
        }()

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text(dateFormatter.string(from: date).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
                    .tracking(0.5)

                Text(DurationFormatter.short(dayTotalSeconds))
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(BrutalTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle().fill(BrutalTheme.border).frame(height: 0.5)
                .padding(.horizontal, 14)

            if let dayLoadError {
                DataLoadErrorView(error: dayLoadError)
                    .padding(14)
            } else if dayHourlyData.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("—")
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary.opacity(0.4))
                    Text("NO SCREEN TIME")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                // Hourly mini timeline
                hourlyMiniTimeline
                    .padding(.top, 10)

                Rectangle().fill(BrutalTheme.border).frame(height: 0.5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)

                // Top apps
                compactTopApps

                Spacer(minLength: 8)
            }
        }
    }

    // MARK: Hourly Mini Timeline

    private var hourlyMiniTimeline: some View {
        let maxSeconds = dayHourlyTotals.map(\.totalSeconds).max() ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            Text("HOURLY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(1)
                .padding(.horizontal, 14)

            // 24 vertical bars
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(dayHourlyTotals) { hourTotal in
                    let fraction = maxSeconds > 0 ? hourTotal.totalSeconds / maxSeconds : 0

                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(
                                hourTotal.totalSeconds > 0
                                    ? BrutalTheme.accent
                                    : BrutalTheme.border.opacity(0.2)
                            )
                            .frame(height: max(2, 70 * fraction))

                        // Label every 6 hours
                        if hourTotal.hour % 6 == 0 {
                            Text(hourLabel(hourTotal.hour))
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textTertiary)
                        } else {
                            Text("")
                                .font(.system(size: 7, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90)
            .padding(.horizontal, 14)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 6: return "6a"
        case 12: return "12p"
        case 18: return "6p"
        default: return "\(hour)"
        }
    }

    // MARK: Compact Top Apps

    private var compactTopApps: some View {
        let display = Array(dayTopApps.prefix(7))
        let maxAppSeconds = display.first?.totalSeconds ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            Text("TOP APPS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(1)
                .padding(.horizontal, 14)

            if display.isEmpty {
                Text("NO APP DATA")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(display.enumerated()), id: \.element.appName) { index, app in
                        let pct = dayTotalSeconds > 0 ? app.totalSeconds / dayTotalSeconds * 100 : 0
                        let barFraction = maxAppSeconds > 0 ? app.totalSeconds / maxAppSeconds : 0

                        VStack(spacing: 3) {
                            HStack(spacing: 0) {
                                // App color indicator
                                Rectangle()
                                    .fill(BrutalTheme.appColors[index % BrutalTheme.appColors.count])
                                    .frame(width: 3, height: 12)
                                    .padding(.trailing, 6)

                                AppNameText(app.appName)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 4)

                                Text(DurationFormatter.short(app.totalSeconds))
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)

                                Text(String(format: "%.0f%%", pct))
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary.opacity(0.7))
                                    .frame(width: 30, alignment: .trailing)
                            }

                            // Proportion bar
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(BrutalTheme.appColors[index % BrutalTheme.appColors.count].opacity(0.2))
                                    .frame(width: geo.size.width * barFraction, height: 2)
                            }
                            .frame(height: 2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)

                        if index < display.count - 1 {
                            Rectangle()
                                .fill(BrutalTheme.border.opacity(0.3))
                                .frame(height: 0.5)
                                .padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func navigateMonth(by value: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newMonth
                selectedDay = nil
            }
        }
    }

    private func intensityColor(fraction: Double) -> Color {
        let clamped = min(max(fraction, 0), 1)
        if clamped == 0 {
            return BrutalTheme.intensity0
        } else if clamped < 0.25 {
            return BrutalTheme.intensity1
        } else if clamped < 0.5 {
            return BrutalTheme.intensity2
        } else if clamped < 0.75 {
            return BrutalTheme.intensity3
        } else {
            return BrutalTheme.intensity4
        }
    }

    private var monthTaskID: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private var selectedDayTaskID: String {
        guard let day = selectedDay else { return "none" }
        return calendar.startOfDay(for: day).description
    }

    // MARK: - Data Loading

    private func loadMonth() async {
        guard let interval = monthInterval else { return }

        let snapshot = FilterSnapshot(
            startDate: interval.start,
            endDate: calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end,
            granularity: .day,
            selectedApps: filters.selectedApps,
            selectedCategories: filters.selectedCategories,
            selectedHeatmapCells: []
        )

        do {
            loadError = nil
            let focusDays = try await appEnvironment.dataService.fetchFocusDays(filters: snapshot)
            var totals: [Date: Double] = [:]
            for day in focusDays {
                totals[calendar.startOfDay(for: day.date)] = day.totalSeconds
            }
            dailyTotals = totals
        } catch {
            loadError = error
            dailyTotals = [:]
        }
    }

    private func loadDayDetail() async {
        guard let day = selectedDay else {
            dayHourlyData = []
            return
        }

        do {
            dayLoadError = nil
            dayHourlyData = try await appEnvironment.dataService.fetchHourlyAppUsage(for: day)
        } catch {
            dayLoadError = error
            dayHourlyData = []
        }
    }
}

// MARK: - Local Models

private struct PanelHourTotal: Identifiable {
    let hour: Int
    let totalSeconds: Double
    var id: Int { hour }
}

private struct PanelAppSummary: Identifiable {
    var id: String { appName }
    let appName: String
    let totalSeconds: Double
}
