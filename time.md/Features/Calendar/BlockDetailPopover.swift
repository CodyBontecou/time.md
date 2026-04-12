import SwiftUI

// MARK: - Hover Tooltip (floating panel on hover)

struct BlockHoverTooltip: View {
    let appName: String
    let color: Color
    let startHour: Int
    let endHour: Int
    let totalSeconds: Double
    /// Actual start time (if available from raw sessions)
    var actualStartTime: Date? = nil
    /// Actual end time (if available from raw sessions)
    var actualEndTime: Date? = nil

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 10, height: 10)

                AppNameText(appName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text(verbatim: timeRange)
                    .font(.system(size: 10))

                Text("·")

                Image(systemName: "timer")
                    .font(.system(size: 9))
                Text(DurationFormatter.short(totalSeconds))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var timeRange: String {
        // Prefer actual times if available
        if let start = actualStartTime, let end = actualEndTime {
            return "\(Self.timeFormatter.string(from: start)) – \(Self.timeFormatter.string(from: end))"
        }
        // Fallback to hour blocks
        return "\(hourString(startHour)) – \(hourString(endHour))"
    }

    private func hourString(_ h: Int) -> String {
        let hour = h % 24
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}

// MARK: - Block Selection Key (stable across re-renders)

struct BlockSelectionKey: Equatable {
    let appName: String
    let startHour: Int
    let endHour: Int
    let date: Date

    init(block: ScreenTimeBlock, date: Date) {
        self.appName = block.appName
        self.startHour = block.startHour
        self.endHour = block.endHour
        self.date = Calendar.current.startOfDay(for: date)
    }

    func matches(_ block: ScreenTimeBlock, on day: Date) -> Bool {
        appName == block.appName
            && startHour == block.startHour
            && endHour == block.endHour
            && Calendar.current.isDate(date, inSameDayAs: day)
    }
}

// MARK: - Detail Sidebar (click to explore)

struct BlockDetailSidebar: View {
    let block: ScreenTimeBlock
    let color: Color
    let date: Date
    let hourlyBreakdown: [Int: Double]
    let weeklyTotals: [Date: Double]?
    let onClose: () -> Void

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    quickStats

                    if !hourlyBreakdown.isEmpty {
                        hourlySection
                    }

                    if let weekly = weeklyTotals, !weekly.isEmpty {
                        weeklySection(weekly)
                    }
                }
                .padding(16)
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .background(CalendarColors.headerBg)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 16, height: 16)

            AppNameText(block.appName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.gray.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Quick Stats

    private var quickStats: some View {
        VStack(spacing: 0) {
            statRow(icon: "timer", label: "Duration", value: DurationFormatter.short(block.totalSeconds), isFirst: true)
            Divider().padding(.horizontal, 12)
            statRow(icon: "clock", label: "Time", value: timeRangeLabel, isFirst: false)
            Divider().padding(.horizontal, 12)
            statRow(icon: "calendar", label: "Date", value: dateLabel, isFirst: false)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CalendarColors.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(CalendarColors.gridLine, lineWidth: 0.5)
        )
    }

    private func statRow(icon: String, label: LocalizedStringKey, value: String, isFirst: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Text(verbatim: value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Hourly Breakdown

    private var hourlySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("HOURLY BREAKDOWN")

            let hours = Array(block.startHour..<block.endHour)
            let maxSec = hourlyBreakdown.values.max() ?? 1

            // Table header
            HStack(spacing: 0) {
                Text("HOUR")
                    .frame(width: 52, alignment: .leading)
                Text("DURATION")
                    .frame(width: 48, alignment: .trailing)
                Spacer()
                Text("SHARE")
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .heavy, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.6))
            .tracking(0.5)

            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)

            ForEach(hours, id: \.self) { hour in
                let sec = hourlyBreakdown[hour] ?? 0
                let frac = maxSec > 0 ? sec / maxSec : 0
                let pct = block.totalSeconds > 0 ? sec / block.totalSeconds * 100 : 0

                HStack(spacing: 6) {
                    Text(hourString(hour))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.08))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.65))
                                .frame(width: max(geo.size.width * frac, sec > 0 ? 2 : 0))
                        }
                    }
                    .frame(height: 14)

                    Text(sec > 0 ? DurationFormatter.short(sec) : "—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(sec > 0 ? .primary : .secondary.opacity(0.4))
                        .frame(width: 38, alignment: .trailing)

                    Text(sec > 0 ? String(format: "%0.0f%%", pct) : "")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .frame(height: 20)
            }

            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)

            // Total row
            HStack {
                Text("TOTAL")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(DurationFormatter.short(block.totalSeconds))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: Weekly Overview

    private func weeklySection(_ totals: [Date: Double]) -> some View {
        let sortedDays = totals.keys.sorted()
        let maxSec = totals.values.max() ?? 1
        let weekTotal = totals.values.reduce(0, +)
        let dayFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "EEE"; return f
        }()
        let dateFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "MMM d"; return f
        }()

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("THIS WEEK")

            ForEach(sortedDays, id: \.self) { day in
                let sec = totals[day] ?? 0
                let frac = maxSec > 0 ? sec / maxSec : 0
                let isCurrent = cal.isDate(day, inSameDayAs: date)

                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(dayFmt.string(from: day).uppercased())
                            .font(.system(size: 9, weight: isCurrent ? .bold : .regular, design: .monospaced))
                        Text(dateFmt.string(from: day))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .frame(width: 40, alignment: .trailing)

                    if isCurrent {
                        Text("▸")
                            .font(.system(size: 8))
                            .foregroundColor(color)
                            .frame(width: 8)
                    } else {
                        Spacer().frame(width: 8)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.06))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(isCurrent ? 0.7 : 0.3))
                                .frame(width: max(geo.size.width * frac, sec > 0 ? 2 : 0))
                        }
                    }
                    .frame(height: 14)

                    Text(sec > 0 ? DurationFormatter.short(sec) : "—")
                        .font(.system(size: 10, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(sec > 0 ? (isCurrent ? .primary : .secondary) : .secondary.opacity(0.4))
                        .frame(width: 44, alignment: .trailing)
                }
                .frame(height: 24)
            }

            Rectangle().fill(CalendarColors.gridLine).frame(height: 0.5)

            HStack {
                Text("WEEK TOTAL")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(DurationFormatter.short(weekTotal))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(.secondary)
            .tracking(1.0)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var timeRangeLabel: String {
        // Prefer actual times if available
        if let start = block.actualStartTime, let end = block.actualEndTime {
            return "\(Self.timeFormatter.string(from: start)) – \(Self.timeFormatter.string(from: end))"
        }
        // Fallback to hour blocks
        return "\(hourString(block.startHour)) – \(hourString(block.endHour))"
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private func hourString(_ h: Int) -> String {
        let hour = h % 24
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}
