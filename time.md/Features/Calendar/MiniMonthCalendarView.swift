import SwiftUI

/// Compact month calendar used in the Day view sidebar and Year view.
struct MiniMonthCalendarView: View {
    let month: Date
    var selectedDate: Date? = nil
    var daysWithData: Set<Int> = []
    var onSelectDay: ((Date) -> Void)? = nil
    var compact: Bool = false

    private let cal = Calendar.current
    private let weekdays = Calendar.current.veryShortWeekdaySymbols

    // MARK: Computed

    private var monthInterval: DateInterval? {
        cal.dateInterval(of: .month, for: month)
    }

    private var days: [Date?] {
        guard let interval = monthInterval else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let blanks = (firstWeekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30

        var result: [Date?] = Array(repeating: nil, count: blanks)
        for offset in 0..<count {
            if let d = cal.date(byAdding: .day, value: offset, to: interval.start) {
                result.append(d)
            }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = compact ? "MMMM" : "MMMM yyyy"
        return f.string(from: month)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            // Month title
            Text(monthLabel)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, compact ? 2 : 4)

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(weekdays, id: \.self) { sym in
                    Text(sym)
                        .font(.system(size: compact ? 8 : 9, weight: .medium))
                        .foregroundColor(CalendarColors.weekdayLabel)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: compact ? 1 : 2) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Text("")
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private var cellSize: CGFloat { compact ? 16 : 22 }

    private func dayCell(for date: Date) -> some View {
        let dayNum = cal.component(.day, from: date)
        let isToday = cal.isDateInToday(date)
        let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let hasData = daysWithData.contains(dayNum)
        let isFuture = date > Date.now

        return Button {
            onSelectDay?(date)
        } label: {
            ZStack {
                if isToday {
                    Circle()
                        .fill(CalendarColors.todayRed)
                        .frame(width: cellSize, height: cellSize)
                } else if isSelected {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: cellSize, height: cellSize)
                }

                Text("\(dayNum)")
                    .font(.system(size: compact ? 9 : 10, weight: isToday ? .bold : .regular))
                    .foregroundColor(
                        isToday ? .white
                            : isFuture ? CalendarColors.dayNumberMuted
                            : CalendarColors.dayNumberDefault
                    )
            }
            .frame(width: cellSize, height: cellSize)
            .overlay(alignment: .bottom) {
                if hasData && !isToday {
                    Circle()
                        .fill(BrutalTheme.accent.opacity(0.6))
                        .frame(width: 3, height: 3)
                        .offset(y: compact ? 1 : 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onSelectDay == nil)
    }
}
