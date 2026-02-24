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
    
    // Advanced time filters
    var timeOfDayRanges: [TimeOfDayRange]
    var weekdayFilter: Set<Int>
    var minDurationSeconds: Double?
    var maxDurationSeconds: Double?

    init(
        startDate: Date = Calendar.current.startOfDay(for: .now),
        endDate: Date = .now,
        granularity: TimeGranularity = .day,
        selectedApps: Set<String> = [],
        selectedCategories: Set<String> = [],
        selectedHeatmapCells: Set<HeatmapCellCoordinate> = [],
        timeOfDayRanges: [TimeOfDayRange] = [],
        weekdayFilter: Set<Int> = [],
        minDurationSeconds: Double? = nil,
        maxDurationSeconds: Double? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.granularity = granularity
        self.selectedApps = selectedApps
        self.selectedCategories = selectedCategories
        self.selectedHeatmapCells = selectedHeatmapCells
        self.timeOfDayRanges = timeOfDayRanges
        self.weekdayFilter = weekdayFilter
        self.minDurationSeconds = minDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
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
            selectedHeatmapCells: selectedHeatmapCells,
            timeOfDayRanges: timeOfDayRanges,
            weekdayFilter: weekdayFilter,
            minDurationSeconds: minDurationSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
    }
    
    /// Check if any advanced time filters are active
    var hasAdvancedFilters: Bool {
        !timeOfDayRanges.isEmpty || !weekdayFilter.isEmpty || minDurationSeconds != nil || maxDurationSeconds != nil
    }
    
    /// Short label describing active advanced filters
    var advancedFiltersLabel: String? {
        var parts: [String] = []
        
        if !timeOfDayRanges.isEmpty {
            let rangeCount = timeOfDayRanges.count
            parts.append(rangeCount == 1 ? "1 time range" : "\(rangeCount) time ranges")
        }
        
        if !weekdayFilter.isEmpty {
            let dayCount = weekdayFilter.count
            parts.append(dayCount == 1 ? "1 day" : "\(dayCount) days")
        }
        
        if minDurationSeconds != nil || maxDurationSeconds != nil {
            parts.append("duration filter")
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    func clearSelections() {
        selectedApps.removeAll()
        selectedCategories.removeAll()
        selectedHeatmapCells.removeAll()
    }
    
    func clearAdvancedFilters() {
        timeOfDayRanges.removeAll()
        weekdayFilter.removeAll()
        minDurationSeconds = nil
        maxDurationSeconds = nil
    }
    
    func clearAllFilters() {
        clearSelections()
        clearAdvancedFilters()
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
