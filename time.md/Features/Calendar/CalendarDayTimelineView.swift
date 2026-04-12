import SwiftUI

// MARK: - App Filter Row (sidebar clickable row with hover)

private struct AppFilterRow: View {
    let appName: String
    let seconds: Double
    let color: Color
    let isFiltered: Bool
    let isVisible: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
                .opacity(isVisible ? 1 : 0.3)

            AppNameText(appName)
                .font(.system(size: 11))
                .foregroundColor(isVisible ? .primary : .secondary.opacity(0.5))
                .lineLimit(1)

            Spacer()

            if isFiltered {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(BrutalTheme.accent)
            }

            Text(DurationFormatter.short(seconds))
                .font(.system(size: 10))
                .foregroundColor(isVisible ? .secondary : .secondary.opacity(0.4))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture { onTap() }
    }
}

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
    @State private var filteredApps: Set<String> = []  // Empty means show all
    
    // Loading state - start true so skeleton shows immediately
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    
    private var showSkeleton: Bool {
        !hasLoadedOnce
    }

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

    /// Blocks filtered by selected apps (empty = show all)
    private var displayedBlocks: [ScreenTimeBlock] {
        if filteredApps.isEmpty { return blocks }
        return blocks.filter { filteredApps.contains($0.appName) }
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
        Group {
            if showSkeleton {
                CalendarDaySkeletonView()
            } else {
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
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSkeleton)
        .task(id: cal.startOfDay(for: date)) {
            await loadDayData()
        }
        .task(id: monthTaskID) {
            await loadMonthTotals()
        }
        .onChange(of: date) { _, _ in
            // Clear selection and filter when navigating days
            selectedBlockKey = nil
            filteredApps = []
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
                Text(verbatim: dayNumber)
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(cal.isDateInToday(date) ? CalendarColors.todayRed : .primary)
                Text(verbatim: dayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(cal.isDateInToday(date) ? CalendarColors.todayRed : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: monthYear)
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
        // Use displayedBlocks for filtered view, but compute layout from all blocks
        // so positions remain stable when filtering
        let allLayouts = CalendarBlockBuilder.computeColumns(for: blocks)

        return GeometryReader { geo in
            let contentWidth = geo.size.width

            ForEach(displayedBlocks) { block in
                if let layout = allLayouts[block.id] {
                    let colWidth = contentWidth / CGFloat(layout.totalColumns)
                    let xOffset = CGFloat(layout.column) * colWidth
                    
                    // Calculate precise Y offset and height from actual times when available
                    let (yOffset, height) = calculateBlockPosition(for: block)
                    
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
                    .frame(width: colWidth - 3, height: max(height, hourHeight * 0.4))
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

                HStack {
                    Text("Apps")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !filteredApps.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filteredApps = []
                            }
                        } label: {
                            Text("Clear")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(BrutalTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 2) {
                    ForEach(Array(topApps.prefix(8).enumerated()), id: \.element.name) { _, app in
                        AppFilterRow(
                            appName: app.name,
                            seconds: app.seconds,
                            color: appColors[app.name] ?? .gray,
                            isFiltered: filteredApps.contains(app.name),
                            isVisible: filteredApps.isEmpty || filteredApps.contains(app.name),
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if filteredApps.contains(app.name) {
                                        filteredApps.remove(app.name)
                                    } else {
                                        filteredApps.insert(app.name)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, -6)  // Offset parent padding so hover bg extends edge-to-edge
            }
            .padding(14)
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
    }

    // MARK: Block Position Calculation
    
    /// Calculate precise Y offset and height for a block based on actual times
    private func calculateBlockPosition(for block: ScreenTimeBlock) -> (yOffset: CGFloat, height: CGFloat) {
        // If we have actual times, use them for precise positioning
        if let startTime = block.actualStartTime, let endTime = block.actualEndTime {
            let startHour = cal.component(.hour, from: startTime)
            let startMinute = cal.component(.minute, from: startTime)
            let endHour = cal.component(.hour, from: endTime)
            let endMinute = cal.component(.minute, from: endTime)
            
            // Calculate fractional hours for precise positioning
            let startFractionalHour = CGFloat(startHour) + CGFloat(startMinute) / 60.0
            let endFractionalHour = CGFloat(endHour) + CGFloat(endMinute) / 60.0
            
            let yOffset = startFractionalHour * hourHeight + 1
            let height = (endFractionalHour - startFractionalHour) * hourHeight - 2
            
            return (yOffset, height)
        }
        
        // Fallback to hour-based positioning
        let yOffset = CGFloat(block.startHour) * hourHeight + 1
        let height = CGFloat(block.endHour - block.startHour) * hourHeight - 2
        return (yOffset, height)
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
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        
        do {
            loadError = nil
            let dayStart = cal.startOfDay(for: date)
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }
            
            // Fetch both hourly data (for stats/totals) and raw sessions (for exact times)
            let data = try await appEnvironment.dataService.fetchHourlyAppUsage(for: date)
            hourlyData = data
            
            // Fetch raw sessions to get actual timestamps
            let sessionFilters = FilterSnapshot(
                startDate: dayStart,
                endDate: dayEnd,
                granularity: .day,
                selectedApps: [],
                selectedCategories: [],
                selectedHeatmapCells: []
            )
            let sessions = try await appEnvironment.dataService.fetchRawSessions(filters: sessionFilters)
            
            // Build colors from hourly data (authoritative source for totals)
            appColors = CalendarBlockBuilder.assignColors(for: data)
            
            // Build blocks using hourly data for totals, sessions for actual times
            blocks = CalendarBlockBuilder.buildBlocksWithActualTimes(hourlyData: data, sessions: sessions, colors: appColors)
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
