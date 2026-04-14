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

    /// Monotonically increasing token that forces views to re-query data.
    /// Increment via `triggerRefresh()` after syncing new data into screentime.db.
    var refreshToken: Int = 0

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

    /// Bump the refresh token to force all views to re-query data.
    func triggerRefresh() {
        refreshToken += 1
    }

    // MARK: - History Cap (Free Tier)

    /// Earliest date a free-tier user may view. Returns `.distantPast` for paid tiers.
    var historyFloor: Date {
        guard StoreManager.shared.tier == .free else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    /// True when the current `startDate` is at or before the free-tier history cap.
    var isAtHistoryLimit: Bool {
        StoreManager.shared.tier == .free && startDate <= historyFloor
    }

    /// Clamp a proposed start date to the history floor.
    private func clamp(_ date: Date) -> Date {
        max(date, historyFloor)
    }

    /// Snap the date range to the current period matching the given granularity.
    func adjustDateRange(for granularity: TimeGranularity) {
        let calendar = Calendar.current
        let now = Date.now

        switch granularity {
        case .day:
            startDate = clamp(calendar.startOfDay(for: now))
            endDate = now
        case .week:
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) {
                startDate = clamp(weekInterval.start)
            } else {
                startDate = clamp(calendar.startOfDay(for: now))
            }
            endDate = now
        case .month:
            if let monthInterval = calendar.dateInterval(of: .month, for: now) {
                startDate = clamp(monthInterval.start)
            } else {
                startDate = clamp(calendar.startOfDay(for: now))
            }
            endDate = now
        case .year:
            if let yearInterval = calendar.dateInterval(of: .year, for: now) {
                startDate = clamp(yearInterval.start)
            } else {
                startDate = clamp(calendar.startOfDay(for: now))
            }
            endDate = now
        }
    }
    
    // MARK: - Time Navigation
    
    /// Whether stepping backward one period is blocked by the free-tier history cap.
    var isAtHistoryFloor: Bool {
        guard StoreManager.shared.tier == .free else { return false }
        return startDate <= historyFloor
    }

    /// Step backward by one period (day, week, month, or year).
    /// No-ops if the resulting start date would be before the history floor.
    func stepBackward() {
        let calendar = Calendar.current

        switch granularity {
        case .day:
            if let newStart = calendar.date(byAdding: .day, value: -1, to: startDate) {
                let clamped = clamp(calendar.startOfDay(for: newStart))
                guard clamped < startDate else { return }
                startDate = clamped
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!.addingTimeInterval(-1)
            }
        case .week:
            if let newStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startDate) {
                let clamped = clamp(newStart)
                guard clamped < startDate else { return }
                startDate = clamped
                endDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate)!.addingTimeInterval(-1)
            }
        case .month:
            if let newStart = calendar.date(byAdding: .month, value: -1, to: startDate) {
                let clamped = clamp(newStart)
                guard clamped < startDate else { return }
                startDate = clamped
                endDate = calendar.date(byAdding: .month, value: 1, to: startDate)!.addingTimeInterval(-1)
            }
        case .year:
            if let newStart = calendar.date(byAdding: .year, value: -1, to: startDate) {
                let clamped = clamp(newStart)
                guard clamped < startDate else { return }
                startDate = clamped
                endDate = calendar.date(byAdding: .year, value: 1, to: startDate)!.addingTimeInterval(-1)
            }
        }
    }
    
    /// Step forward by one period (day, week, month, or year)
    func stepForward() {
        let calendar = Calendar.current
        let now = Date.now
        
        switch granularity {
        case .day:
            if let newStart = calendar.date(byAdding: .day, value: 1, to: startDate) {
                let newStartOfDay = calendar.startOfDay(for: newStart)
                let todayStart = calendar.startOfDay(for: now)
                
                if newStartOfDay <= todayStart {
                    startDate = newStartOfDay
                    if newStartOfDay == todayStart {
                        endDate = now
                    } else {
                        endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!.addingTimeInterval(-1)
                    }
                }
            }
        case .week:
            if let newStart = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate),
               let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
               newStart <= currentWeekStart {
                startDate = newStart
                if newStart == currentWeekStart {
                    endDate = now
                } else {
                    endDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate)!.addingTimeInterval(-1)
                }
            }
        case .month:
            if let newStart = calendar.date(byAdding: .month, value: 1, to: startDate),
               let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start,
               newStart <= currentMonthStart {
                startDate = newStart
                if newStart == currentMonthStart {
                    endDate = now
                } else {
                    endDate = calendar.date(byAdding: .month, value: 1, to: startDate)!.addingTimeInterval(-1)
                }
            }
        case .year:
            if let newStart = calendar.date(byAdding: .year, value: 1, to: startDate),
               let currentYearStart = calendar.dateInterval(of: .year, for: now)?.start,
               newStart <= currentYearStart {
                startDate = newStart
                if newStart == currentYearStart {
                    endDate = now
                } else {
                    endDate = calendar.date(byAdding: .year, value: 1, to: startDate)!.addingTimeInterval(-1)
                }
            }
        }
    }
    
    /// Jump back to today/current period
    func goToToday() {
        adjustDateRange(for: granularity)
    }
    
    /// Whether the current view is showing the current period (today, this week, etc.)
    var isCurrentPeriod: Bool {
        let calendar = Calendar.current
        let now = Date.now
        
        switch granularity {
        case .day:
            return calendar.isDateInToday(startDate)
        case .week:
            guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return false }
            return calendar.isDate(startDate, inSameDayAs: currentWeekStart)
        case .month:
            return calendar.isDate(startDate, equalTo: now, toGranularity: .month)
        case .year:
            return calendar.isDate(startDate, equalTo: now, toGranularity: .year)
        }
    }
    
    /// Human-readable label for the current period
    var periodLabel: String {
        let calendar = Calendar.current
        let now = Date.now
        
        switch granularity {
        case .day:
            if calendar.isDateInToday(startDate) {
                return "Today"
            } else if calendar.isDateInYesterday(startDate) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                if calendar.isDate(startDate, equalTo: now, toGranularity: .year) {
                    formatter.dateFormat = "E, MMM d"
                } else {
                    formatter.dateFormat = "E, MMM d, yyyy"
                }
                return formatter.string(from: startDate)
            }
            
        case .week:
            let formatter = DateFormatter()
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: startDate) ?? endDate
            
            if isCurrentPeriod {
                return "This Week"
            } else if let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now),
                      calendar.isDate(startDate, inSameDayAs: lastWeekStart) {
                return "Last Week"
            } else if calendar.isDate(startDate, equalTo: now, toGranularity: .year) {
                formatter.dateFormat = "MMM d"
                return "\(formatter.string(from: startDate)) – \(formatter.string(from: weekEnd))"
            } else {
                formatter.dateFormat = "MMM d, yyyy"
                return "\(formatter.string(from: startDate)) – \(formatter.string(from: weekEnd))"
            }
            
        case .month:
            let formatter = DateFormatter()
            if isCurrentPeriod {
                return "This Month"
            } else if let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: calendar.dateInterval(of: .month, for: now)?.start ?? now),
                      calendar.isDate(startDate, equalTo: lastMonthStart, toGranularity: .month) {
                return "Last Month"
            } else if calendar.isDate(startDate, equalTo: now, toGranularity: .year) {
                formatter.dateFormat = "MMMM"
            } else {
                formatter.dateFormat = "MMMM yyyy"
            }
            return formatter.string(from: startDate)
            
        case .year:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            if isCurrentPeriod {
                return "This Year"
            } else if let lastYearStart = calendar.date(byAdding: .year, value: -1, to: calendar.dateInterval(of: .year, for: now)?.start ?? now),
                      calendar.isDate(startDate, equalTo: lastYearStart, toGranularity: .year) {
                return "Last Year"
            }
            return formatter.string(from: startDate)
        }
    }
}
