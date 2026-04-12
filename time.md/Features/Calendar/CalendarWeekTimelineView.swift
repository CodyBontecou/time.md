import SwiftUI

// MARK: - Week Block Cell (isolated hover state — no parent re-render)

private struct WeekBlockCell: View {
    let block: ScreenTimeBlock
    let color: Color
    let width: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var showTooltip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppNameText(block.appName)
                .font(.system(size: width > 80 ? 10 : 8, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            if block.endHour - block.startHour >= 2 && width > 60 {
                Text(DurationFormatter.short(block.totalSeconds))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(isHovered || isSelected ? 1.0 : 0.85))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.white.opacity(isHovered || isSelected ? 0.5 : 0), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                // Debounced tooltip — small delay prevents flicker
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if isHovered && !isSelected { showTooltip = true }
                }
            } else {
                showTooltip = false
            }
        }
        .overlay(alignment: .top) {
            if showTooltip && !isSelected {
                BlockHoverTooltip(
                    appName: block.appName,
                    color: color,
                    startHour: block.startHour,
                    endHour: block.endHour,
                    totalSeconds: block.totalSeconds,
                    actualStartTime: block.actualStartTime,
                    actualEndTime: block.actualEndTime
                )
                .fixedSize()
                .offset(y: -52)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .offset(y: 4)))
                .animation(.easeOut(duration: 0.15), value: showTooltip)
            }
        }
        .onTapGesture {
            showTooltip = false
            onTap()
        }
        .onChange(of: isSelected) { _, selected in
            if selected { showTooltip = false }
        }
    }
}

// MARK: - Week Timeline View

struct CalendarWeekTimelineView: View {
    @Binding var date: Date
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var weeklyData: [Date: [HourlyAppUsage]] = [:]
    @State private var weekBlocks: [Date: [ScreenTimeBlock]] = [:]
    @State private var weekAppColors: [String: Color] = [:]
    @State private var loadError: Error?
    @State private var selectedBlockKey: BlockSelectionKey?
    
    // Loading state - start true so skeleton shows immediately
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    
    private var showSkeleton: Bool {
        !hasLoadedOnce
    }

    private let cal = Calendar.current
    private let hourHeight: CGFloat = 52
    private let timeColWidth: CGFloat = 56
    private let sidebarWidth: CGFloat = 260

    // MARK: Computed

    private var weekStart: Date {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else {
            return cal.startOfDay(for: date)
        }
        return interval.start
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Resolved detail info for the currently selected block.
    private var selectedDetail: (block: ScreenTimeBlock, color: Color, date: Date, hourly: [Int: Double], weekly: [Date: Double])? {
        guard let key = selectedBlockKey else { return nil }
        for (day, blocks) in weekBlocks {
            if let block = blocks.first(where: { key.matches($0, on: day) }) {
                let color = weekAppColors[block.appName] ?? block.color
                return (block, color, day, hourlyBreakdownForApp(block.appName, on: day), weeklyTotalsForApp(block.appName))
            }
        }
        return nil
    }

    // MARK: Body

    var body: some View {
        Group {
            if showSkeleton {
                CalendarWeekSkeletonView()
            } else {
                HStack(spacing: 0) {
                    // Main timeline
                    VStack(spacing: 0) {
                        dayHeaders
                        Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)
                        timelineScroll
                    }

                    // Detail sidebar (slides in on selection)
                    if let detail = selectedDetail {
                        Rectangle().fill(CalendarColors.gridLine).frame(width: 0.5)

                        BlockDetailSidebar(
                            block: detail.block,
                            color: detail.color,
                            date: detail.date,
                            hourlyBreakdown: detail.hourly,
                            weeklyTotals: detail.weekly,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedBlockKey = nil }
                            }
                        )
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSkeleton)
        .animation(.easeInOut(duration: 0.2), value: selectedBlockKey)
        .task(id: weekStart) {
            await loadWeekData()
        }
    }

    // MARK: Day Headers

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColWidth, height: 0)

            ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                if index > 0 {
                    Rectangle().fill(CalendarColors.gridLine).frame(width: 0.5)
                }
                dayHeaderCell(for: day).frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .background(CalendarColors.headerBg)
    }

    private func dayHeaderCell(for day: Date) -> some View {
        let isToday = cal.isDateInToday(day)
        let dayNum = cal.component(.day, from: day)
        let f = DateFormatter()
        f.dateFormat = "EEE"
        let weekday = f.string(from: day).uppercased()
        let dayData = weeklyData[cal.startOfDay(for: day)] ?? []
        let totalSeconds = dayData.reduce(0) { $0 + $1.totalSeconds }

        return VStack(spacing: 3) {
            Text(verbatim: weekday)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isToday ? CalendarColors.todayRed : CalendarColors.weekdayLabel)

            ZStack {
                if isToday {
                    Circle().fill(CalendarColors.todayRed).frame(width: 26, height: 26)
                }
                Text("\(dayNum)")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(isToday ? .white : .primary)
            }

            if totalSeconds > 0 {
                Text(DurationFormatter.short(totalSeconds))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Time Labels

    private var timeLabelsColumn: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Text(hourLabel(hour))
                            .font(.system(size: 10))
                            .foregroundColor(CalendarColors.hourText)
                            .padding(.trailing, 8)
                    }
                    .offset(y: -6)
                    Spacer()
                }
                .frame(width: timeColWidth, height: hourHeight)
                .id("week-hour-\(hour)")
            }
        }
    }

    // MARK: Timeline

    private var timelineScroll: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                HStack(spacing: 0) {
                    timeLabelsColumn

                    ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                        if index > 0 {
                            Rectangle().fill(CalendarColors.gridLine).frame(width: 0.5)
                        }
                        dayColumn(for: day)
                    }
                }
                .frame(height: 24 * hourHeight)
                .padding(.bottom, 20)
            }
            .scrollClipDisabled()
            .scrollIndicators(.never)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.none) {
                        scrollProxy.scrollTo("week-hour-\(firstActiveHour)", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: Day Column

    private func dayColumn(for day: Date) -> some View {
        let dayStart = cal.startOfDay(for: day)
        let dayBlocks = weekBlocks[dayStart] ?? []
        let columnLayouts = CalendarBlockBuilder.computeColumns(for: dayBlocks)

        return ZStack(alignment: .topLeading) {
            // Hour grid lines
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)
                        Spacer()
                    }
                    .frame(height: hourHeight)
                }
            }

            // Blocks
            GeometryReader { geo in
                let colWidth = geo.size.width

                ForEach(dayBlocks) { block in
                    if let layout = columnLayouts[block.id] {
                        let segWidth = colWidth / CGFloat(layout.totalColumns) - 2
                        let xOff = CGFloat(layout.column) * (colWidth / CGFloat(layout.totalColumns)) + 1
                        let yOff = CGFloat(block.startHour) * hourHeight + 1
                        let h = CGFloat(block.endHour - block.startHour) * hourHeight - 2
                        let color = weekAppColors[block.appName] ?? block.color
                        let key = BlockSelectionKey(block: block, date: dayStart)
                        let isSelected = selectedBlockKey == key

                        WeekBlockCell(
                            block: block,
                            color: color,
                            width: segWidth,
                            isSelected: isSelected,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedBlockKey = isSelected ? nil : key
                                }
                            }
                        )
                        .frame(width: max(segWidth, 20), height: max(h, hourHeight * 0.5))
                        .offset(x: xOff, y: yOff)
                        .zIndex(isSelected ? 10 : 0)
                    }
                }
            }

            // Current time line
            if cal.isDateInToday(day) {
                currentTimeLine
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24 * hourHeight)
    }

    private var currentTimeLine: some View {
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let y = CGFloat(hour) * hourHeight + CGFloat(minute) / 60.0 * hourHeight

        return Rectangle()
            .fill(CalendarColors.currentTimeLine)
            .frame(height: 1.5)
            .offset(y: y)
    }

    // MARK: Data Helpers

    private func hourlyBreakdownForApp(_ appName: String, on day: Date) -> [Int: Double] {
        let dayStart = cal.startOfDay(for: day)
        guard let data = weeklyData[dayStart] else { return [:] }
        var result: [Int: Double] = [:]
        for entry in data where entry.appName == appName {
            result[entry.hour] = entry.totalSeconds
        }
        return result
    }

    private func weeklyTotalsForApp(_ appName: String) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for (day, data) in weeklyData {
            let total = data.filter { $0.appName == appName }.reduce(0) { $0 + $1.totalSeconds }
            result[day] = total
        }
        return result
    }

    private var firstActiveHour: Int {
        let allHours = weeklyData.values.flatMap { $0 }.filter { $0.totalSeconds > 30 }.map(\.hour)
        return allHours.min() ?? 7
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    // MARK: Data Loading

    private func loadWeekData() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        
        var hourlyResult: [Date: [HourlyAppUsage]] = [:]
        var sessionsResult: [Date: [RawSession]] = [:]

        await withTaskGroup(of: (Date, [HourlyAppUsage], [RawSession]).self) { group in
            for day in weekDays {
                group.addTask {
                    let dayStart = cal.startOfDay(for: day)
                    guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
                        return (dayStart, [], [])
                    }
                    
                    let data = (try? await appEnvironment.dataService.fetchHourlyAppUsage(for: day)) ?? []
                    
                    // Fetch raw sessions for actual times
                    let sessionFilters = FilterSnapshot(
                        startDate: dayStart,
                        endDate: dayEnd,
                        granularity: .day,
                        selectedApps: [],
                        selectedCategories: [],
                        selectedHeatmapCells: []
                    )
                    let sessions = (try? await appEnvironment.dataService.fetchRawSessions(filters: sessionFilters)) ?? []
                    
                    return (dayStart, data, sessions)
                }
            }
            for await (dayStart, data, sessions) in group {
                hourlyResult[dayStart] = data
                sessionsResult[dayStart] = sessions
            }
        }

        weeklyData = hourlyResult

        // Compute colors from all hourly data (authoritative source for totals)
        let allHourlyData = hourlyResult.values.flatMap { $0 }
        weekAppColors = CalendarBlockBuilder.assignColors(for: allHourlyData)

        // Compute blocks using hourly data for totals, sessions for actual times
        var blocks: [Date: [ScreenTimeBlock]] = [:]
        for (day, hourlyData) in hourlyResult {
            let sessions = sessionsResult[day] ?? []
            blocks[day] = CalendarBlockBuilder.buildBlocksWithActualTimes(hourlyData: hourlyData, sessions: sessions, colors: weekAppColors)
        }
        weekBlocks = blocks
    }
}
