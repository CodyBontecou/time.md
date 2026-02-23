import Foundation

enum TimeGranularity: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct FilterSnapshot {
    var startDate: Date
    var endDate: Date
    var granularity: TimeGranularity
    var selectedApps: Set<String>
    var selectedCategories: Set<String>
    var selectedHeatmapCells: Set<HeatmapCellCoordinate>
}

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let totalSeconds: Double
}

struct AppUsageSummary: Identifiable {
    var id: String { appName }
    let appName: String
    let totalSeconds: Double
    let sessionCount: Int
}

struct CategoryUsageSummary: Identifiable {
    var id: String { category }
    let category: String
    let totalSeconds: Double
}

struct AppCategoryMapping: Identifiable {
    var id: String { appName }
    let appName: String
    let category: String
}

struct SessionBucket: Identifiable {
    let id = UUID()
    let label: String
    let sessionCount: Int
}

struct HeatmapCellCoordinate: Hashable {
    let weekday: Int
    let hour: Int
}

struct HeatmapCell: Identifiable {
    var id: String { "\(weekday)-\(hour)" }
    let weekday: Int
    let hour: Int
    let totalSeconds: Double
}

struct FocusDay: Identifiable {
    var id: Date { date }
    let date: Date
    let focusBlocks: Int
    let totalSeconds: Double
}

struct DashboardSummary {
    let totalSeconds: Double
    let averageDailySeconds: Double
    let focusBlocks: Int
    let currentStreakDays: Int
}

struct HourlyAppUsage: Identifiable {
    var id: String { "\(hour)-\(appName)" }
    let hour: Int // 0–23
    let appName: String
    let totalSeconds: Double
}

struct DailyAppBreakdown: Identifiable {
    let id = UUID()
    let date: Date
    let appName: String
    let totalSeconds: Double
}
