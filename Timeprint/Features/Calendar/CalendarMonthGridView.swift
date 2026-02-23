import SwiftUI

/// Apple Calendar-style Month view — grid of day cells with screentime event entries.
struct CalendarMonthGridView: View {
    @Binding var date: Date
    let filters: GlobalFilterStore
    var onSelectDay: ((Date) -> Void)? = nil

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var dailyTotals: [Date: Double] = [:]
    @State private var dailyApps: [Date: [DailyAppBreakdown]] = [:]
    @State private var loadError: Error?

    private let cal = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    // MARK: Computed

    private var monthInterval: DateInterval? {
        cal.dateInterval(of: .month, for: date)
    }

    private var calendarDays: [Date?] {
        guard let interval = monthInterval else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let blanks = (firstWeekday - cal.firstWeekday + 7) % 7
        let daysInMonth = cal.range(of: .day, in: .month, for: date)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: blanks)
        for offset in 0..<daysInMonth {
            if let d = cal.date(byAdding: .day, value: offset, to: interval.start) {
                days.append(d)
            }
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private var weekCount: Int {
        calendarDays.count / 7
    }

    /// Top app names (by total usage this month) for consistent color assignment.
    /// Uses alphabetical tiebreaker so colors are stable when usage values are equal.
    private var orderedAppNames: [String] {
        var totals: [String: Double] = [:]
        for apps in dailyApps.values {
            for app in apps { totals[app.appName, default: 0] += app.totalSeconds }
        }
        return totals.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }.map(\.key)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Weekday header row
            weekdayHeader

            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)

            // Day grid — fills available space
            GeometryReader { geo in
                let rowHeight = geo.size.height / CGFloat(weekCount)

                VStack(spacing: 0) {
                    ForEach(0..<weekCount, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let index = week * 7 + col
                                let dayDate = calendarDays[index]

                                if col > 0 {
                                    Rectangle().fill(CalendarColors.gridLineFaint).frame(width: 0.5)
                                }

                                if let dayDate {
                                    monthDayCell(for: dayDate, height: rowHeight)
                                } else {
                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(height: rowHeight)

                        if week < weekCount - 1 {
                            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .task(id: monthTaskID) {
            await loadMonthData()
        }
    }

    // MARK: Weekday Header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, sym in
                if index > 0 {
                    Rectangle().fill(CalendarColors.gridLineFaint).frame(width: 0.5)
                }

                Text(sym.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CalendarColors.weekdayLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(CalendarColors.headerBg)
    }

    // MARK: Day Cell

    private func monthDayCell(for dayDate: Date, height: CGFloat) -> some View {
        let dayNum = cal.component(.day, from: dayDate)
        let isToday = cal.isDateInToday(dayDate)
        let isFuture = dayDate > Date.now
        let dayStart = cal.startOfDay(for: dayDate)
        let totalSeconds = dailyTotals[dayStart] ?? 0
        let apps = dailyApps[dayStart] ?? []
        // Show top 3 apps that fit
        let maxEvents = max(Int((height - 30) / 16), 0)
        let visibleApps = Array(apps.prefix(min(3, maxEvents)))
        let moreCount = apps.count - visibleApps.count

        return Button {
            onSelectDay?(dayDate)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                // Day number
                HStack {
                    ZStack {
                        if isToday {
                            Circle()
                                .fill(CalendarColors.todayRed)
                                .frame(width: 22, height: 22)
                        }

                        Text("\(dayNum)")
                            .font(.system(size: 11, weight: isToday ? .bold : .regular))
                            .foregroundColor(
                                isToday ? .white
                                    : isFuture ? CalendarColors.dayNumberMuted
                                    : .primary
                            )
                    }

                    Spacer()

                    if totalSeconds > 0 {
                        Text(DurationFormatter.short(totalSeconds))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 3)

                // App event entries
                ForEach(Array(visibleApps.enumerated()), id: \.offset) { index, app in
                    appEventRow(app: app, index: index)
                }

                if moreCount > 0 {
                    Text("+\(moreCount) more")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isFuture ? CalendarColors.gridLineFaint.opacity(0.3) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appEventRow(app: DailyAppBreakdown, index: Int) -> some View {
        let colorIndex = orderedAppNames.firstIndex(of: app.appName) ?? index
        let color = BrutalTheme.appColors[colorIndex % BrutalTheme.appColors.count]

        return HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: 12)

            AppNameText(app.appName)
                .font(.system(size: 9))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            Text(DurationFormatter.short(app.totalSeconds))
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.horizontal, 2)
    }

    // MARK: Helpers

    private var monthTaskID: String {
        let c = cal.dateComponents([.year, .month], from: date)
        return "month-\(c.year ?? 0)-\(c.month ?? 0)"
    }

    // MARK: Data Loading

    private func loadMonthData() async {
        guard let interval = monthInterval else { return }

        let endDate = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let snapshot = FilterSnapshot(
            startDate: interval.start,
            endDate: endDate,
            granularity: .day,
            selectedApps: filters.selectedApps,
            selectedCategories: filters.selectedCategories,
            selectedHeatmapCells: []
        )

        do {
            loadError = nil

            async let focusDaysTask = appEnvironment.dataService.fetchFocusDays(filters: snapshot)
            async let breakdownTask = appEnvironment.dataService.fetchDailyAppBreakdown(filters: snapshot, topN: 10)

            let focusDays = try await focusDaysTask
            let breakdown = try await breakdownTask

            // Daily totals
            var totals: [Date: Double] = [:]
            for day in focusDays {
                totals[cal.startOfDay(for: day.date)] = day.totalSeconds
            }
            dailyTotals = totals

            // Daily app breakdown grouped by day
            var apps: [Date: [DailyAppBreakdown]] = [:]
            for entry in breakdown {
                let dayStart = cal.startOfDay(for: entry.date)
                apps[dayStart, default: []].append(entry)
            }
            // Sort each day's apps by seconds descending
            for key in apps.keys {
                apps[key]?.sort { $0.totalSeconds > $1.totalSeconds }
            }
            dailyApps = apps
        } catch {
            loadError = error
            dailyTotals = [:]
            dailyApps = [:]
        }
    }
}
