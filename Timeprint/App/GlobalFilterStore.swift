import Foundation
import Observation

@Observable
final class GlobalFilterStore {
    var startDate: Date
    var endDate: Date
    var granularity: TimeGranularity
    var selectedApps: Set<String>
    var selectedCategories: Set<String>
    var selectedHeatmapCells: Set<HeatmapCellCoordinate>

    init(
        startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now,
        endDate: Date = .now,
        granularity: TimeGranularity = .day,
        selectedApps: Set<String> = [],
        selectedCategories: Set<String> = [],
        selectedHeatmapCells: Set<HeatmapCellCoordinate> = []
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.granularity = granularity
        self.selectedApps = selectedApps
        self.selectedCategories = selectedCategories
        self.selectedHeatmapCells = selectedHeatmapCells
    }

    var rangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var snapshot: FilterSnapshot {
        FilterSnapshot(
            startDate: startDate,
            endDate: endDate,
            granularity: granularity,
            selectedApps: selectedApps,
            selectedCategories: selectedCategories,
            selectedHeatmapCells: selectedHeatmapCells
        )
    }

    func clearSelections() {
        selectedApps.removeAll()
        selectedCategories.removeAll()
        selectedHeatmapCells.removeAll()
    }

    /// Snap the date range to the current period matching the given granularity.
    func adjustDateRange(for granularity: TimeGranularity) {
        let calendar = Calendar.current
        let now = Date.now

        switch granularity {
        case .day:
            startDate = calendar.startOfDay(for: now)
            endDate = now
        case .week:
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) {
                startDate = weekInterval.start
            } else {
                startDate = calendar.startOfDay(for: now)
            }
            endDate = now
        case .month:
            if let monthInterval = calendar.dateInterval(of: .month, for: now) {
                startDate = monthInterval.start
            } else {
                startDate = calendar.startOfDay(for: now)
            }
            endDate = now
        case .year:
            if let yearInterval = calendar.dateInterval(of: .year, for: now) {
                startDate = yearInterval.start
            } else {
                startDate = calendar.startOfDay(for: now)
            }
            endDate = now
        }
    }
}
