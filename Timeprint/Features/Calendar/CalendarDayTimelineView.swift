import SwiftUI

// MARK: - Day Block Cell (isolated hover state)

private struct DayBlockCell: View {
    let block: ScreenTimeBlock
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    var onHoverChanged: ((Bool) -> Void)? = nil

    @State private var isHovered = false
    @State private var showTooltip = false

    var body: some View {
        let durationHours = block.endHour - block.startHour

        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 1) {
                AppNameText(block.appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if durationHours >= 1 {
                    Text(DurationFormatter.short(block.totalSeconds))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)

            Spacer(minLength: 0)
        }
        .background(color.opacity(isHovered || isSelected ? 0.22 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color.opacity(isHovered || isSelected ? 0.4 : 0), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged?(hovering)
            if hovering {
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
                    totalSeconds: block.totalSeconds
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

// MARK: - Day Timeline View

struct CalendarDayTimelineView: View {
    @Binding var date: Date
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var hourlyData: [HourlyAppUsage] = []
    @State private var blocks: [ScreenTimeBlock] = []
    @State private var appColors: [String: Color] = [:]
    @State private var dailyTotals: [Date: Double] = [:]
    @State private var loadError: Error?
    @State private var selectedBlockKey: BlockSelectionKey?
    @State private var hoveredBlockID: String?

    private let cal = Calendar.current
    private let hourHeight: CGFloat = 52
    private let timeColWidth: CGFloat = 56
    private let sidebarWidth: CGFloat = 240

    private var totalDaySeconds: Double {
        hourlyData.reduce(0) { $0 + $1.totalSeconds }
    }

    private var topApps: [(name: String, seconds: Double)] {
        var byApp: [String: Double] = [:]
        for entry in hourlyData { byApp[entry.appName, default: 0] += entry.totalSeconds }
        return byApp.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var daysWithData: Set<Int> {
        Set(dailyTotals.compactMap { (date, secs) -> Int? in
            guard secs > 0,
                  cal.isDate(date, equalTo: self.date, toGranularity: .month)
            else { return nil }
            return cal.component(.day, from: date)
        })
    }

    /// Resolved detail for selected block.
    private var selectedDetail: (block: ScreenTimeBlock, color: Color)? {
        guard let key = selectedBlockKey else { return nil }
        if let block = blocks.first(where: { key.matches($0, on: date) }) {
            let color = appColors[block.appName] ?? block.color
            return (block, color)
        }
        return nil
    }

    // MARK: Date display

    private var dayNumber: String { "\(cal.component(.day, from: date))" }

    private var dayName: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: date)
    }

    private var monthYear: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: date)
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            // Timeline
            VStack(spacing: 0) {
                dayHeader
                Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)
                timelineScrollView
            }
            .zIndex(1)

            Rectangle().fill(CalendarColors.gridLine).frame(width: 0.5)

            // Right sidebar — swaps between default stats and block detail
            sidebarContent
                .frame(width: sidebarWidth)
                .animation(.easeInOut(duration: 0.2), value: selectedBlockKey)
        }
        .task(id: cal.startOfDay(for: date)) {
            await loadDayData()
        }
        .task(id: monthTaskID) {
            await loadMonthTotals()
        }
        .onChange(of: date) { _, _ in
            // Clear selection when navigating days
            selectedBlockKey = nil
        }
    }

    // MARK: Sidebar content switcher

    @ViewBuilder
    private var sidebarContent: some View {
        if let detail = selectedDetail {
            BlockDetailSidebar(
                block: detail.block,
                color: detail.color,
                date: date,
                hourlyBreakdown: hourlyBreakdownForApp(detail.block.appName),
                weeklyTotals: nil,
                onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedBlockKey = nil }
                }
            )
            .transition(.opacity)
        } else {
            defaultSidebar
                .transition(.opacity)
        }
    }

    // MARK: Day Header

    private var dayHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(dayNumber)
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(cal.isDateInToday(date) ? CalendarColors.todayRed : .primary)
                Text(dayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(cal.isDateInToday(date) ? CalendarColors.todayRed : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(monthYear)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if totalDaySeconds > 0 {
                    Text(DurationFormatter.short(totalDaySeconds))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BrutalTheme.accent)
                }
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CalendarColors.headerBg)
    }

    // MARK: Timeline

    private var timelineScrollView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    blocksOverlay.padding(.leading, timeColWidth)
                    if cal.isDateInToday(date) { currentTimeIndicator }
                }
                .frame(height: 24 * hourHeight)
                .padding(.bottom, 20)
                .id("timeline")
            }
            .scrollClipDisabled()
            .scrollIndicators(.never)
            .onAppear {
                let scrollHour = firstActiveHour ?? 7
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.none) {
                        scrollProxy.scrollTo("hour-\(scrollHour)", anchor: .top)
                    }
                }
            }
        }
    }

    private var firstActiveHour: Int? {
        hourlyData.filter { $0.totalSeconds > 30 }.map(\.hour).min()
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(hourLabel(hour))
                        .font(.system(size: 10))
                        .foregroundColor(CalendarColors.hourText)
                        .frame(width: timeColWidth, alignment: .trailing)
                        .padding(.trailing, 8)
                        .offset(y: -6)

                    VStack(spacing: 0) {
                        Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)
                        Spacer()
                    }
                }
                .frame(height: hourHeight)
                .id("hour-\(hour)")
            }
        }
    }

    private var blocksOverlay: some View {
        let currentBlocks = blocks
        let currentLayouts = CalendarBlockBuilder.computeColumns(for: currentBlocks)

        return GeometryReader { geo in
            let contentWidth = geo.size.width

            ForEach(currentBlocks) { block in
                if let layout = currentLayouts[block.id] {
                    let colWidth = contentWidth / CGFloat(layout.totalColumns)
                    let xOffset = CGFloat(layout.column) * colWidth
                    let yOffset = CGFloat(block.startHour) * hourHeight + 1
                    let height = CGFloat(block.endHour - block.startHour) * hourHeight - 2
                    let color = appColors[block.appName] ?? block.color
                    let key = BlockSelectionKey(block: block, date: date)
                    let isSelected = selectedBlockKey == key

                    DayBlockCell(
                        block: block,
                        color: color,
                        isSelected: isSelected,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedBlockKey = isSelected ? nil : key
                            }
                        },
                        onHoverChanged: { hovering in
                            hoveredBlockID = hovering ? block.id : nil
                        }
                    )
                    .offset(x: xOffset + 1, y: yOffset)
                    .frame(width: colWidth - 3, height: max(height, hourHeight * 0.6))
                    .zIndex(isSelected ? 20 : (hoveredBlockID == block.id ? 10 : 0))
                }
            }
        }
    }

    private var currentTimeIndicator: some View {
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let y = CGFloat(hour) * hourHeight + CGFloat(minute) / 60.0 * hourHeight

        return HStack(spacing: 0) {
            Spacer().frame(width: timeColWidth - 4)
            Circle().fill(CalendarColors.currentTimeLine).frame(width: 8, height: 8)
            Rectangle().fill(CalendarColors.currentTimeLine).frame(height: 1)
        }
        .offset(y: y - 4)
    }

    // MARK: Default Sidebar

    private var defaultSidebar: some View {
        VStack(spacing: 0) {
            MiniMonthCalendarView(
                month: date,
                selectedDate: date,
                daysWithData: daysWithData,
                onSelectDay: { day in
                    withAnimation(.easeInOut(duration: 0.15)) { date = day }
                }
            )
            .padding(14)

            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)
                .padding(.horizontal, 14)

            if totalDaySeconds > 0 {
                dayStatsPanel
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No screen time")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .background(CalendarColors.headerBg)
    }

    private var dayStatsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Screen Time")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(DurationFormatter.short(totalDaySeconds))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)

                Text("Apps")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                ForEach(Array(topApps.prefix(8).enumerated()), id: \.element.name) { _, app in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(appColors[app.name] ?? .gray)
                            .frame(width: 10, height: 10)

                        AppNameText(app.name)
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(DurationFormatter.short(app.seconds))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
    }

    // MARK: Data Helpers

    private func hourlyBreakdownForApp(_ appName: String) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for entry in hourlyData where entry.appName == appName {
            result[entry.hour] = entry.totalSeconds
        }
        return result
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    private var monthTaskID: String {
        let c = cal.dateComponents([.year, .month], from: date)
        return "m-\(c.year ?? 0)-\(c.month ?? 0)"
    }

    // MARK: Data Loading

    private func loadDayData() async {
        do {
            loadError = nil
            let data = try await appEnvironment.dataService.fetchHourlyAppUsage(for: date)
            hourlyData = data
            blocks = CalendarBlockBuilder.buildBlocks(from: data)
            appColors = CalendarBlockBuilder.assignColors(for: data)
        } catch {
            loadError = error
            hourlyData = []
            blocks = []
            appColors = [:]
        }
    }

    private func loadMonthTotals() async {
        guard let interval = cal.dateInterval(of: .month, for: date) else { return }
        let snapshot = FilterSnapshot(
            startDate: interval.start,
            endDate: cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end,
            granularity: .day,
            selectedApps: filters.selectedApps,
            selectedCategories: filters.selectedCategories,
            selectedHeatmapCells: []
        )
        do {
            let focusDays = try await appEnvironment.dataService.fetchFocusDays(filters: snapshot)
            var totals: [Date: Double] = [:]
            for day in focusDays { totals[cal.startOfDay(for: day.date)] = day.totalSeconds }
            dailyTotals = totals
        } catch {
            dailyTotals = [:]
        }
    }
}
