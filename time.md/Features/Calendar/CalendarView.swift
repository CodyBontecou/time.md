import Charts
import SwiftUI

struct CalendarView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var displayedMonth: Date = .now
    @State private var dailyTotals: [Date: Double] = [:]
    @State private var selectedDay: Date?
    @State private var loadError: Error?

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    // MARK: - Computed

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

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
                // ─── Title ───
                Text("CALENDAR.")
                    .font(BrutalTheme.displayFont)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .tracking(1)

                Rectangle()
                    .fill(BrutalTheme.borderStrong)
                    .frame(height: 2)

                if let loadError {
                    DataLoadErrorView(error: loadError)
                }

                // ─── Month Navigation ───
                GlassCard {
                    VStack(spacing: 16) {
                        HStack {
                            Button {
                                navigateMonth(by: -1)
                            } label: {
                                Text("←")
                                    .font(.system(size: 18, weight: .black, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textPrimary)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text(verbatim: monthTitle)
                                .font(BrutalTheme.headingFont)
                                .foregroundColor(BrutalTheme.textPrimary)
                                .tracking(2)

                            Spacer()

                            Button {
                                navigateMonth(by: 1)
                            } label: {
                                Text("→")
                                    .font(.system(size: 18, weight: .black, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }

                        // Today button
                        if !calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    displayedMonth = .now
                                }
                            } label: {
                                Text("TODAY")
                                    .font(BrutalTheme.captionMono)
                                    .tracking(1)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(BrutalTheme.accent)
                            }
                        }

                        // Weekday header
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                            ForEach(weekdaySymbols, id: \.self) { symbol in
                                Text(verbatim: symbol.uppercased())
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .tracking(0.5)
                                    .frame(maxWidth: .infinity)
                                    .padding(.bottom, 8)
                            }
                        }

                        // Day cells
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                            ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                                if let date {
                                    dayCell(for: date)
                                } else {
                                    Color.clear
                                        .frame(height: 64)
                                }
                            }
                        }
                    }
                }

                // ─── Legend ───
                Text(BrutalTheme.sectionLabel(1, "INTENSITY"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                HStack(spacing: 0) {
                    Text("LESS")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .tracking(0.5)
                        .padding(.trailing, 8)

                    ForEach(0..<5) { level in
                        Rectangle()
                            .fill(intensityColor(fraction: Double(level) / 4.0))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(BrutalTheme.border, lineWidth: 0.5)
                            )
                    }

                    Text("MORE")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .tracking(0.5)
                        .padding(.leading, 8)
                }

                // ─── Month summary ───
                if !dailyTotals.isEmpty {
                    monthSummarySection
                }

                // Day detail (inline)
                if let selectedDay {
                    CalendarDayDetailView(date: selectedDay)
                }
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .task(id: monthTaskID) {
            await loadMonth()
        }
    }

    // MARK: - Day cell

    private func dayCell(for date: Date) -> some View {
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
            VStack(spacing: 3) {
                Text("\(dayNumber)")
                    .font(BrutalTheme.bodyMono)
                    .fontWeight(isToday ? .black : .regular)
                    .foregroundColor(isToday ? BrutalTheme.accent : isFuture ? BrutalTheme.textTertiary : BrutalTheme.textPrimary)

                if totalSeconds > 0 {
                    Text(DurationFormatter.short(totalSeconds))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(intensityColor(fraction: fraction).opacity(0.35))
            .overlay(
                Rectangle()
                    .strokeBorder(
                        isSelected ? BrutalTheme.accent : BrutalTheme.border.opacity(0.3),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            .overlay(alignment: .top) {
                if isToday {
                    Rectangle()
                        .fill(BrutalTheme.accent)
                        .frame(width: 16, height: 2)
                        .offset(y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month summary

    private var monthSummarySection: some View {
        let totals = Array(dailyTotals.values)
        let totalSeconds = totals.reduce(0, +)
        let activeDays = totals.filter { $0 > 0 }.count
        let avgSeconds = activeDays > 0 ? totalSeconds / Double(activeDays) : 0
        let peakDay = dailyTotals.max(by: { $0.value < $1.value })

        return VStack(alignment: .leading, spacing: 12) {
            Text(BrutalTheme.sectionLabel(2, "MONTH SUMMARY"))
                .font(BrutalTheme.headingFont)
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1.5)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 0)], spacing: 0) {
                summaryMetric(title: "TOTAL", value: DurationFormatter.short(totalSeconds))
                summaryMetric(title: "ACTIVE DAYS", value: "\(activeDays)")
                summaryMetric(title: "DAILY AVG", value: DurationFormatter.short(avgSeconds))
                if let peakDay {
                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "MMM d"
                    summaryMetric(title: "PEAK", value: "\(formatter.string(from: peakDay.key)) — \(DurationFormatter.short(peakDay.value))")
                }
            }
            .overlay(
                Rectangle()
                    .strokeBorder(BrutalTheme.border, lineWidth: BrutalTheme.borderWidth)
            )
        }
    }

    private func summaryMetric(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(0.5)
            Text(verbatim: value)
                .font(BrutalTheme.metricSmall)
                .foregroundColor(BrutalTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrutalTheme.cardPadding)
        .background(BrutalTheme.surface)
        .overlay(
            Rectangle()
                .strokeBorder(BrutalTheme.border, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

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
}
