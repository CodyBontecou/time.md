import Foundation

// Note: Core types (FilterSnapshot, TimeGranularity, SparklinePoint, AppUsageSummary,
// CategoryUsageSummary, FocusDay, DashboardSummary, TrendPoint, HeatmapCell,
// SessionBucket, HeatmapCellCoordinate, TimeOfDayRange) are defined in
// Shared/Models/SharedAnalyticsModels.swift for cross-platform use.

// MARK: - macOS-specific analytics models

struct AppCategoryMapping: Identifiable {
    var id: String { appName }
    let appName: String
    let category: String
}

struct HourlyAppUsage: Identifiable {
    var id: String { "\(hour)-\(appName)" }
    let hour: Int // 0–23
    let appName: String
    let totalSeconds: Double
}

/// App usage aggregated by weekday + hour for heatmap cell selection.
struct HeatmapCellAppUsage: Identifiable {
    var id: String { "\(weekday)-\(hour)-\(appName)" }
    let weekday: Int // 0 = Sun ... 6 = Sat
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

// MARK: - Phase 2 — Enriched overview models

/// Today's high-level summary with delta comparison to yesterday.
struct TodaySummary: Sendable {
    let todayTotalSeconds: Double
    let yesterdayTotalSeconds: Double
    let peakHour: Int          // 0–23
    let peakHourSeconds: Double
    let appsUsedCount: Int
    let topAppName: String
    let topAppSeconds: Double

    /// Percentage change vs yesterday. Positive means today is higher.
    var deltaPercent: Double {
        guard yesterdayTotalSeconds > 0 else { return todayTotalSeconds > 0 ? 100 : 0 }
        return ((todayTotalSeconds - yesterdayTotalSeconds) / yesterdayTotalSeconds) * 100
    }
}

/// Period-aware summary with delta comparison to the previous period.
struct PeriodSummary: Sendable {
    let granularity: TimeGranularity
    let totalSeconds: Double
    let previousTotalSeconds: Double
    let peakHour: Int          // 0–23
    let peakHourSeconds: Double
    let appsUsedCount: Int
    let topAppName: String
    let topAppSeconds: Double

    /// Percentage change vs previous period. Positive means current is higher.
    var deltaPercent: Double {
        guard previousTotalSeconds > 0 else { return totalSeconds > 0 ? 100 : 0 }
        return ((totalSeconds - previousTotalSeconds) / previousTotalSeconds) * 100
    }

    /// Human-readable label for the current period (e.g., "TODAY", "THIS WEEK").
    var periodLabel: String {
        switch granularity {
        case .day: return "TODAY"
        case .week: return "THIS WEEK"
        case .month: return "THIS MONTH"
        case .year: return "THIS YEAR"
        }
    }

    /// Human-readable comparison label (e.g., "vs yesterday", "vs last week").
    var comparisonLabel: String {
        switch granularity {
        case .day: return "vs yesterday"
        case .week: return "vs last week"
        case .month: return "vs last month"
        case .year: return "vs last year"
        }
    }

    /// Short label for context (e.g., "today", "this week").
    var contextLabel: String {
        switch granularity {
        case .day: return "today"
        case .week: return "this week"
        case .month: return "this month"
        case .year: return "this year"
        }
    }
}

/// The longest uninterrupted usage session in a given time range.
struct LongestSession: Sendable {
    let appName: String
    let durationSeconds: Double
    let startDate: Date
}

/// Compact heatmap data for the overview mini-heatmap.
struct MiniHeatmapData: Sendable {
    let cells: [HeatmapCell]
    let maxSeconds: Double
}

// MARK: - Phase 4 — Analytics engine models

/// Context switch rate for a given hour in a given day.
struct ContextSwitchPoint: Identifiable, Sendable {
    var id: String { "\(date)-\(hour)" }
    let date: Date
    let hour: Int        // 0–23
    let switchCount: Int // number of app→app transitions
}

/// A single app→app transition and how often it occurred.
struct AppTransition: Identifiable, Sendable {
    var id: String { "\(fromApp)→\(toApp)" }
    let fromApp: String
    let toApp: String
    let count: Int
}

/// Average usage per weekday (Mon/Tue/…).
struct WeekdayAverage: Identifiable, Sendable {
    var id: Int { weekday }
    let weekday: Int              // 0 = Sun, 6 = Sat
    let averageSeconds: Double
    let topApp: String
}

/// Delta between two time periods.
struct PeriodDelta: Sendable {
    let currentTotalSeconds: Double
    let previousTotalSeconds: Double
    let percentChange: Double         // +/- %
    let currentAppsUsed: Int
    let previousAppsUsed: Int
    let appDeltas: [AppDelta]
}

/// Per-app change between two periods.
struct AppDelta: Identifiable, Sendable {
    var id: String { appName }
    let appName: String
    let currentSeconds: Double
    let previousSeconds: Double

    var percentChange: Double {
        guard previousSeconds > 0 else { return currentSeconds > 0 ? 100 : 0 }
        return ((currentSeconds - previousSeconds) / previousSeconds) * 100
    }
}

/// A human-readable insight string with optional metadata.
struct Insight: Identifiable, Sendable {
    let id = UUID()
    let icon: String        // SF Symbol name
    let text: String
    let sentiment: InsightSentiment
}

enum InsightSentiment: Sendable {
    case positive   // down arrow / green
    case negative   // up arrow / red
    case neutral    // info / gray
}

// MARK: - Phase E1 — Raw Session Export

/// A single, non-aggregated usage session for granular export.
struct RawSession: Identifiable, Sendable {
    let id = UUID()
    let appName: String
    let startTime: Date
    let endTime: Date
    let durationSeconds: Double
}
