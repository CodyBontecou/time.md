import Foundation

// MARK: - Shared models for cross-platform use

/// A single entry in a lightweight sparkline series.
struct SparklinePoint: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let totalSeconds: Double
}

/// Summary of app usage for display
struct AppUsageSummary: Identifiable, Sendable {
    var id: String { appName }
    let appName: String
    let totalSeconds: Double
    let sessionCount: Int
}

/// Category usage summary
struct CategoryUsageSummary: Identifiable, Sendable {
    var id: String { category }
    let category: String
    let totalSeconds: Double
}

/// Focus day data
struct FocusDay: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let focusBlocks: Int
    let totalSeconds: Double
}

/// Dashboard summary
struct DashboardSummary: Sendable {
    let totalSeconds: Double
    let averageDailySeconds: Double
    let focusBlocks: Int
}

/// Trend point for charts
struct TrendPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let totalSeconds: Double
}

/// Heatmap cell
struct HeatmapCell: Identifiable, Sendable {
    var id: String { "\(weekday)-\(hour)" }
    let weekday: Int
    let hour: Int
    let totalSeconds: Double
}

/// Session distribution bucket
struct SessionBucket: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let sessionCount: Int
}

/// Heatmap cell coordinate for filtering
struct HeatmapCellCoordinate: Hashable, Sendable {
    let weekday: Int
    let hour: Int
}

/// Time granularity for aggregation
enum TimeGranularity: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

/// Filter snapshot for querying data
struct FilterSnapshot: Sendable {
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
        startDate: Date,
        endDate: Date,
        granularity: TimeGranularity,
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
    
    var hasAdvancedFilters: Bool {
        !timeOfDayRanges.isEmpty || !weekdayFilter.isEmpty || minDurationSeconds != nil || maxDurationSeconds != nil
    }
}

/// A time-of-day range (e.g., 9am-5pm work hours)
struct TimeOfDayRange: Hashable, Codable, Identifiable, Sendable {
    let id: UUID
    var startHour: Int
    var endHour: Int
    
    init(startHour: Int = 9, endHour: Int = 17) {
        self.id = UUID()
        self.startHour = max(0, min(23, startHour))
        self.endHour = max(0, min(23, endHour))
    }
    
    var displayName: String {
        let startStr = formatHour(startHour)
        let endStr = formatHour(endHour)
        if startHour == endHour {
            return startStr
        }
        return "\(startStr) – \(endStr)"
    }
    
    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h12) \(ampm)"
    }
    
    func contains(hour: Int) -> Bool {
        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            return hour >= startHour || hour < endHour
        }
    }
}
