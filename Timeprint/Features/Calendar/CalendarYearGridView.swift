import SwiftUI

/// Apple Calendar-style Year view — 4×3 grid of mini month calendars.
struct CalendarYearGridView: View {
    @Binding var date: Date
    let filters: GlobalFilterStore
    var onSelectMonth: ((Date) -> Void)? = nil

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var yearlyDayData: Set<String> = [] // "yyyy-MM-dd" strings for days with data
    @State private var loadError: Error?

    private let cal = Calendar.current

    // MARK: Computed

    private var year: Int {
        cal.component(.year, from: date)
    }

    private var months: [Date] {
        (1...12).compactMap { month in
            cal.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 4),
                spacing: 24
            ) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                    yearMonthCell(for: month)
                }
            }
            .padding(24)
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .task(id: year) {
            await loadYearData()
        }
    }

    // MARK: Month Cell

    private func yearMonthCell(for month: Date) -> some View {
        let daysWithData = daysWithDataSet(for: month)

        return Button {
            onSelectMonth?(month)
        } label: {
            MiniMonthCalendarView(
                month: month,
                daysWithData: daysWithData,
                compact: true
            )
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(CalendarColors.headerBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(CalendarColors.gridLine, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: Helpers

    private func daysWithDataSet(for month: Date) -> Set<Int> {
        let yearVal = cal.component(.year, from: month)
        let monthVal = cal.component(.month, from: month)
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30

        var result: Set<Int> = []
        for day in 1...daysInMonth {
            let key = String(format: "%04d-%02d-%02d", yearVal, monthVal, day)
            if yearlyDayData.contains(key) {
                result.insert(day)
            }
        }
        return result
    }

    // MARK: Data Loading

    private func loadYearData() async {
        guard let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = cal.date(from: DateComponents(year: year, month: 12, day: 31))
        else { return }

        let snapshot = FilterSnapshot(
            startDate: yearStart,
            endDate: yearEnd,
            granularity: .day,
            selectedApps: filters.selectedApps,
            selectedCategories: filters.selectedCategories,
            selectedHeatmapCells: []
        )

        do {
            loadError = nil
            let focusDays = try await appEnvironment.dataService.fetchFocusDays(filters: snapshot)

            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"

            var daySet: Set<String> = []
            for day in focusDays where day.totalSeconds > 0 {
                daySet.insert(f.string(from: day.date))
            }
            yearlyDayData = daySet
        } catch {
            loadError = error
            yearlyDayData = []
        }
    }
}
