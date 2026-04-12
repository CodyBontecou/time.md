import SwiftUI

// MARK: - View Mode

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

// MARK: - Screen Time Block (timeline event model)

struct ScreenTimeBlock: Identifiable {
    /// Deterministic ID so SwiftUI can track blocks across re-renders.
    let id: String
    let appName: String
    let startHour: Int
    let endHour: Int       // exclusive
    let totalSeconds: Double
    let color: Color
    /// Actual start time of the first session in this block (for precise display)
    let actualStartTime: Date?
    /// Actual end time of the last session in this block (for precise display)
    let actualEndTime: Date?

    init(appName: String, startHour: Int, endHour: Int, totalSeconds: Double, color: Color, actualStartTime: Date? = nil, actualEndTime: Date? = nil) {
        self.id = "\(appName)|\(startHour)-\(endHour)"
        self.appName = appName
        self.startHour = startHour
        self.endHour = endHour
        self.totalSeconds = totalSeconds
        self.color = color
        self.actualStartTime = actualStartTime
        self.actualEndTime = actualEndTime
    }
}

// MARK: - Block Layout Info

struct BlockLayoutInfo {
    let column: Int
    let totalColumns: Int
}

// MARK: - Calendar Theme (Adaptive Light/Dark Mode)

enum CalendarColors {
    static let todayRed = Color.red
    static let gridLine = Color.primary.opacity(0.08)
    static let gridLineFaint = Color.primary.opacity(0.05)
    static let hourText = Color.secondary
    static let background = Color(nsColor: .windowBackgroundColor)
    static let headerBg = Color(nsColor: .controlBackgroundColor)
    static let dayNumberDefault = Color.primary
    static let dayNumberMuted = Color.secondary
    static let weekdayLabel = Color.secondary
    static let currentTimeLine = Color.red
}

// MARK: - Helpers

enum CalendarBlockBuilder {
    /// Convert hourly app usage data into merged timeline blocks.
    static func buildBlocks(from hourlyData: [HourlyAppUsage]) -> [ScreenTimeBlock] {
        let appColors = assignColors(for: hourlyData)

        // Group by app
        var appHours: [String: [(hour: Int, seconds: Double)]] = [:]
        for entry in hourlyData where entry.totalSeconds > 30 {
            appHours[entry.appName, default: []].append((entry.hour, entry.totalSeconds))
        }

        var blocks: [ScreenTimeBlock] = []

        for (appName, hours) in appHours {
            let sorted = hours.sorted { $0.hour < $1.hour }
            guard !sorted.isEmpty else { continue }

            var start = sorted[0].hour
            var end = sorted[0].hour + 1
            var total = sorted[0].seconds

            for i in 1..<sorted.count {
                if sorted[i].hour == end {
                    end = sorted[i].hour + 1
                    total += sorted[i].seconds
                } else {
                    blocks.append(ScreenTimeBlock(
                        appName: appName,
                        startHour: start, endHour: end,
                        totalSeconds: total,
                        color: appColors[appName] ?? .gray
                    ))
                    start = sorted[i].hour
                    end = sorted[i].hour + 1
                    total = sorted[i].seconds
                }
            }
            blocks.append(ScreenTimeBlock(
                appName: appName,
                startHour: start, endHour: end,
                totalSeconds: total,
                color: appColors[appName] ?? .gray
            ))
        }

        return blocks
    }

    /// Build blocks from hourly data, enhanced with actual times from raw sessions.
    /// Uses hourly data for accurate totals, raw sessions only for precise timestamps.
    static func buildBlocksWithActualTimes(hourlyData: [HourlyAppUsage], sessions: [RawSession], colors: [String: Color]) -> [ScreenTimeBlock] {
        let calendar = Calendar.current
        
        // First, extract actual times from sessions grouped by app+hour
        struct SessionHourKey: Hashable {
            let appName: String
            let hour: Int
        }
        
        var sessionTimes: [SessionHourKey: (earliest: Date, latest: Date)] = [:]
        for session in sessions {
            let hour = calendar.component(.hour, from: session.startTime)
            let key = SessionHourKey(appName: session.appName, hour: hour)
            if let existing = sessionTimes[key] {
                sessionTimes[key] = (
                    earliest: min(existing.earliest, session.startTime),
                    latest: max(existing.latest, session.endTime)
                )
            } else {
                sessionTimes[key] = (earliest: session.startTime, latest: session.endTime)
            }
        }
        
        // Group hourly data by app
        var appHours: [String: [(hour: Int, seconds: Double)]] = [:]
        for entry in hourlyData where entry.totalSeconds > 30 {
            appHours[entry.appName, default: []].append((entry.hour, entry.totalSeconds))
        }
        
        var blocks: [ScreenTimeBlock] = []
        
        for (appName, hours) in appHours {
            let sorted = hours.sorted { $0.hour < $1.hour }
            guard !sorted.isEmpty else { continue }
            
            var startHour = sorted[0].hour
            var endHour = sorted[0].hour + 1
            var totalSeconds = sorted[0].seconds
            
            // Get actual times for first hour
            let firstKey = SessionHourKey(appName: appName, hour: sorted[0].hour)
            var actualStart = sessionTimes[firstKey]?.earliest
            var actualEnd = sessionTimes[firstKey]?.latest
            
            for i in 1..<sorted.count {
                if sorted[i].hour == endHour {
                    // Consecutive hour - merge
                    endHour = sorted[i].hour + 1
                    totalSeconds += sorted[i].seconds
                    
                    // Update actual times
                    let key = SessionHourKey(appName: appName, hour: sorted[i].hour)
                    if let times = sessionTimes[key] {
                        if let start = actualStart {
                            actualStart = min(start, times.earliest)
                        } else {
                            actualStart = times.earliest
                        }
                        if let end = actualEnd {
                            actualEnd = max(end, times.latest)
                        } else {
                            actualEnd = times.latest
                        }
                    }
                } else {
                    // Gap - finalize current block
                    blocks.append(ScreenTimeBlock(
                        appName: appName,
                        startHour: startHour,
                        endHour: endHour,
                        totalSeconds: totalSeconds,
                        color: colors[appName] ?? .gray,
                        actualStartTime: actualStart,
                        actualEndTime: actualEnd
                    ))
                    
                    // Start new block
                    startHour = sorted[i].hour
                    endHour = sorted[i].hour + 1
                    totalSeconds = sorted[i].seconds
                    
                    let key = SessionHourKey(appName: appName, hour: sorted[i].hour)
                    actualStart = sessionTimes[key]?.earliest
                    actualEnd = sessionTimes[key]?.latest
                }
            }
            
            // Finalize last block
            blocks.append(ScreenTimeBlock(
                appName: appName,
                startHour: startHour,
                endHour: endHour,
                totalSeconds: totalSeconds,
                color: colors[appName] ?? .gray,
                actualStartTime: actualStart,
                actualEndTime: actualEnd
            ))
        }
        
        return blocks
    }

    /// Assign consistent colors ranked by total usage.
    /// Uses alphabetical tiebreaker so colors are stable when usage values are equal.
    static func assignColors(for hourlyData: [HourlyAppUsage]) -> [String: Color] {
        var totals: [String: Double] = [:]
        for entry in hourlyData {
            totals[entry.appName, default: 0] += entry.totalSeconds
        }
        let sorted = totals.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        var colors: [String: Color] = [:]
        for (index, item) in sorted.enumerated() {
            colors[item.key] = BrutalTheme.appColors[index % BrutalTheme.appColors.count]
        }
        return colors
    }

    /// Compute column assignments for overlapping blocks.
    static func computeColumns(for blocks: [ScreenTimeBlock]) -> [String: BlockLayoutInfo] {
        let sorted = blocks.sorted {
            if $0.startHour != $1.startHour { return $0.startHour < $1.startHour }
            return ($0.endHour - $0.startHour) > ($1.endHour - $1.startHour)
        }

        var columnEnds: [Int] = [] // endHour per column
        var assignments: [(String, Int)] = []

        for block in sorted {
            var placed = false
            for (i, endHour) in columnEnds.enumerated() {
                if block.startHour >= endHour {
                    columnEnds[i] = block.endHour
                    assignments.append((block.id, i))
                    placed = true
                    break
                }
            }
            if !placed {
                assignments.append((block.id, columnEnds.count))
                columnEnds.append(block.endHour)
            }
        }

        let totalCols = max(columnEnds.count, 1)
        var result: [String: BlockLayoutInfo] = [:]
        for (id, col) in assignments {
            result[id] = BlockLayoutInfo(column: col, totalColumns: totalCols)
        }
        return result
    }
}

// MARK: - Main Calendar View

struct AppleCalendarView: View {
    let filters: GlobalFilterStore
    @Binding var isExpanded: Bool

    @State private var displayedDate: Date = .now

    private let cal = Calendar.current

    /// Map the global granularity to a calendar view mode.
    private var viewMode: CalendarViewMode {
        switch filters.granularity {
        case .day:   return .day
        case .week:  return .week
        case .month: return .month
        case .year:  return .year
        }
    }

    // MARK: Title

    private var headerTitle: String {
        let f = DateFormatter()
        switch viewMode {
        case .day:
            f.dateFormat = "EEEE, MMMM d, yyyy"
        case .week, .month:
            f.dateFormat = "MMMM yyyy"
        case .year:
            f.dateFormat = "yyyy"
        }
        return f.string(from: displayedDate)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)

            Group {
                switch viewMode {
                case .day:
                    CalendarDayTimelineView(
                        date: $displayedDate,
                        filters: filters
                    )
                case .week:
                    CalendarWeekTimelineView(
                        date: $displayedDate,
                        filters: filters
                    )
                case .month:
                    CalendarMonthGridView(
                        date: $displayedDate,
                        filters: filters,
                        onSelectDay: { day in
                            displayedDate = day
                            withAnimation(.easeInOut(duration: 0.2)) { filters.granularity = .day }
                        }
                    )
                case .year:
                    CalendarYearGridView(
                        date: $displayedDate,
                        filters: filters,
                        onSelectMonth: { month in
                            displayedDate = month
                            withAnimation(.easeInOut(duration: 0.2)) { filters.granularity = .month }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(CalendarColors.background)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 8))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 0 : 8)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .onExitCommand {
            guard isExpanded else { return }
            isExpanded = false
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Nav arrows
            HStack(spacing: 2) {
                navButton(systemImage: "chevron.left", direction: -1)
                navButton(systemImage: "chevron.right", direction: 1)
            }

            // Today
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { displayedDate = .now }
            } label: {
                Text("Today")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            // Title
            Text(verbatim: headerTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            // Expand / Collapse
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse calendar" : "Expand calendar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CalendarColors.headerBg)
    }

    private func navButton(systemImage: String, direction: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { navigate(by: direction) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func navigate(by direction: Int) {
        switch viewMode {
        case .day:
            displayedDate = cal.date(byAdding: .day, value: direction, to: displayedDate) ?? displayedDate
        case .week:
            displayedDate = cal.date(byAdding: .weekOfYear, value: direction, to: displayedDate) ?? displayedDate
        case .month:
            displayedDate = cal.date(byAdding: .month, value: direction, to: displayedDate) ?? displayedDate
        case .year:
            displayedDate = cal.date(byAdding: .year, value: direction, to: displayedDate) ?? displayedDate
        }
    }
}
