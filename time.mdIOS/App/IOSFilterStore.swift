import SwiftUI
import Combine

/// iOS-specific filter store for managing time and data filters
@MainActor
final class IOSFilterStore: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Date range granularity
    @Published var granularity: TimeGranularity = .day {
        didSet {
            adjustDateRangeForGranularity()
            UserDefaults.standard.set(granularity.rawValue, forKey: "ios_filter_granularity")
        }
    }
    
    /// Start date for filtering
    @Published var startDate: Date = Calendar.current.startOfDay(for: .now)
    
    /// End date for filtering
    @Published var endDate: Date = .now
    
    /// Time of day ranges (e.g., 9am-5pm work hours)
    @Published var timeOfDayRanges: [TimeOfDayRange] = [] {
        didSet { persistTimeRanges() }
    }
    
    /// Selected weekdays (0 = Sunday, 1 = Monday, etc.)
    @Published var selectedWeekdays: Set<Int> = [] {
        didSet { persistWeekdays() }
    }
    
    /// Minimum session duration filter (in seconds)
    @Published var minDurationSeconds: Double? = nil {
        didSet { UserDefaults.standard.set(minDurationSeconds as Any, forKey: "ios_filter_min_duration") }
    }
    
    /// Maximum session duration filter (in seconds)
    @Published var maxDurationSeconds: Double? = nil {
        didSet { UserDefaults.standard.set(maxDurationSeconds as Any, forKey: "ios_filter_max_duration") }
    }
    
    /// Quick time slot presets
    @Published var selectedTimeSlot: TimeSlotPreset? = nil {
        didSet { applyTimeSlotPreset() }
    }
    
    // MARK: - Computed Properties
    
    /// Check if any filters are active
    var hasActiveFilters: Bool {
        !timeOfDayRanges.isEmpty ||
        !selectedWeekdays.isEmpty ||
        minDurationSeconds != nil ||
        maxDurationSeconds != nil ||
        selectedTimeSlot != nil
    }
    
    /// Summary label for active filters
    var activeFiltersLabel: String? {
        var parts: [String] = []
        
        if let slot = selectedTimeSlot {
            parts.append(slot.name)
        } else if !timeOfDayRanges.isEmpty {
            parts.append("\(timeOfDayRanges.count) time range\(timeOfDayRanges.count == 1 ? "" : "s")")
        }
        
        if !selectedWeekdays.isEmpty {
            if selectedWeekdays.count == 5 && selectedWeekdays == Set([1, 2, 3, 4, 5]) {
                parts.append("Weekdays")
            } else if selectedWeekdays.count == 2 && selectedWeekdays == Set([0, 6]) {
                parts.append("Weekend")
            } else {
                parts.append("\(selectedWeekdays.count) day\(selectedWeekdays.count == 1 ? "" : "s")")
            }
        }
        
        if minDurationSeconds != nil || maxDurationSeconds != nil {
            parts.append("Duration")
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    /// Date range label for display
    var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        switch granularity {
        case .day:
            if Calendar.current.isDateInToday(startDate) {
                return "Today"
            } else if Calendar.current.isDateInYesterday(startDate) {
                return "Yesterday"
            }
            return formatter.string(from: startDate)
        case .week:
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: startDate)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: startDate)
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Restore persisted settings
        if let savedGranularity = UserDefaults.standard.string(forKey: "ios_filter_granularity"),
           let granularity = TimeGranularity(rawValue: savedGranularity) {
            self.granularity = granularity
        }
        
        if let minDuration = UserDefaults.standard.object(forKey: "ios_filter_min_duration") as? Double {
            self.minDurationSeconds = minDuration
        }
        
        if let maxDuration = UserDefaults.standard.object(forKey: "ios_filter_max_duration") as? Double {
            self.maxDurationSeconds = maxDuration
        }
        
        restoreTimeRanges()
        restoreWeekdays()
        adjustDateRangeForGranularity()
    }
    
    // MARK: - Date Navigation
    
    /// Move to previous period
    func goToPreviousPeriod() {
        let calendar = Calendar.current
        switch granularity {
        case .day:
            if let newStart = calendar.date(byAdding: .day, value: -1, to: startDate) {
                startDate = calendar.startOfDay(for: newStart)
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate)?.addingTimeInterval(-1) ?? startDate
            }
        case .week:
            if let newStart = calendar.date(byAdding: .weekOfYear, value: -1, to: startDate) {
                startDate = newStart
                endDate = calendar.date(byAdding: .day, value: 6, to: startDate) ?? startDate
            }
        case .month:
            if let newStart = calendar.date(byAdding: .month, value: -1, to: startDate) {
                startDate = newStart
                if let interval = calendar.dateInterval(of: .month, for: startDate) {
                    endDate = interval.end.addingTimeInterval(-1)
                }
            }
        case .year:
            if let newStart = calendar.date(byAdding: .year, value: -1, to: startDate) {
                startDate = newStart
                if let interval = calendar.dateInterval(of: .year, for: startDate) {
                    endDate = interval.end.addingTimeInterval(-1)
                }
            }
        }
    }
    
    /// Move to next period
    func goToNextPeriod() {
        let calendar = Calendar.current
        let now = Date()
        
        switch granularity {
        case .day:
            if let newStart = calendar.date(byAdding: .day, value: 1, to: startDate),
               newStart <= now {
                startDate = calendar.startOfDay(for: newStart)
                endDate = min(calendar.date(byAdding: .day, value: 1, to: startDate)?.addingTimeInterval(-1) ?? startDate, now)
            }
        case .week:
            if let newStart = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate),
               newStart <= now {
                startDate = newStart
                endDate = min(calendar.date(byAdding: .day, value: 6, to: startDate) ?? startDate, now)
            }
        case .month:
            if let newStart = calendar.date(byAdding: .month, value: 1, to: startDate),
               newStart <= now {
                startDate = newStart
                if let interval = calendar.dateInterval(of: .month, for: startDate) {
                    endDate = min(interval.end.addingTimeInterval(-1), now)
                }
            }
        case .year:
            if let newStart = calendar.date(byAdding: .year, value: 1, to: startDate),
               newStart <= now {
                startDate = newStart
                if let interval = calendar.dateInterval(of: .year, for: startDate) {
                    endDate = min(interval.end.addingTimeInterval(-1), now)
                }
            }
        }
    }
    
    /// Reset to current period
    func goToCurrentPeriod() {
        adjustDateRangeForGranularity()
    }
    
    /// Check if we're viewing the current period
    var isCurrentPeriod: Bool {
        let calendar = Calendar.current
        let now = Date()
        
        switch granularity {
        case .day:
            return calendar.isDateInToday(startDate)
        case .week:
            if let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: now) {
                return startDate >= currentWeekInterval.start && startDate < currentWeekInterval.end
            }
            return false
        case .month:
            return calendar.isDate(startDate, equalTo: now, toGranularity: .month)
        case .year:
            return calendar.isDate(startDate, equalTo: now, toGranularity: .year)
        }
    }
    
    // MARK: - Filter Actions
    
    /// Clear all filters
    func clearAllFilters() {
        timeOfDayRanges.removeAll()
        selectedWeekdays.removeAll()
        minDurationSeconds = nil
        maxDurationSeconds = nil
        selectedTimeSlot = nil
    }
    
    /// Add a custom time range
    func addTimeRange(_ range: TimeOfDayRange) {
        selectedTimeSlot = nil // Clear preset when adding custom
        timeOfDayRanges.append(range)
    }
    
    /// Remove a time range
    func removeTimeRange(at index: Int) {
        guard timeOfDayRanges.indices.contains(index) else { return }
        timeOfDayRanges.remove(at: index)
        if timeOfDayRanges.isEmpty {
            selectedTimeSlot = nil
        }
    }
    
    /// Toggle a weekday selection
    func toggleWeekday(_ day: Int) {
        if selectedWeekdays.contains(day) {
            selectedWeekdays.remove(day)
        } else {
            selectedWeekdays.insert(day)
        }
    }
    
    /// Apply weekdays preset
    func applyWeekdaysPreset() {
        selectedWeekdays = Set([1, 2, 3, 4, 5])
    }
    
    /// Apply weekend preset
    func applyWeekendPreset() {
        selectedWeekdays = Set([0, 6])
    }
    
    // MARK: - Filter Snapshot
    
    /// Generate a FilterSnapshot for data queries
    func makeFilterSnapshot() -> FilterSnapshot {
        FilterSnapshot(
            startDate: startDate,
            endDate: endDate,
            granularity: granularity,
            selectedApps: [],
            selectedCategories: [],
            selectedHeatmapCells: [],
            timeOfDayRanges: timeOfDayRanges,
            weekdayFilter: selectedWeekdays,
            minDurationSeconds: minDurationSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
    }
    
    // MARK: - Private Helpers
    
    private func adjustDateRangeForGranularity() {
        let calendar = Calendar.current
        let now = Date()
        
        switch granularity {
        case .day:
            startDate = calendar.startOfDay(for: now)
            endDate = now
        case .week:
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) {
                startDate = weekInterval.start
                endDate = now
            }
        case .month:
            if let monthInterval = calendar.dateInterval(of: .month, for: now) {
                startDate = monthInterval.start
                endDate = now
            }
        case .year:
            if let yearInterval = calendar.dateInterval(of: .year, for: now) {
                startDate = yearInterval.start
                endDate = now
            }
        }
    }
    
    private func applyTimeSlotPreset() {
        guard let slot = selectedTimeSlot else { return }
        timeOfDayRanges = [TimeOfDayRange(startHour: slot.startHour, endHour: slot.endHour)]
    }
    
    private func persistTimeRanges() {
        let encoded = timeOfDayRanges.map { ["start": $0.startHour, "end": $0.endHour] }
        UserDefaults.standard.set(encoded, forKey: "ios_filter_time_ranges")
    }
    
    private func restoreTimeRanges() {
        guard let saved = UserDefaults.standard.array(forKey: "ios_filter_time_ranges") as? [[String: Int]] else { return }
        timeOfDayRanges = saved.compactMap { dict in
            guard let start = dict["start"], let end = dict["end"] else { return nil }
            return TimeOfDayRange(startHour: start, endHour: end)
        }
    }
    
    private func persistWeekdays() {
        UserDefaults.standard.set(Array(selectedWeekdays), forKey: "ios_filter_weekdays")
    }
    
    private func restoreWeekdays() {
        if let saved = UserDefaults.standard.array(forKey: "ios_filter_weekdays") as? [Int] {
            selectedWeekdays = Set(saved)
        }
    }
}

// MARK: - Time Slot Presets

enum TimeSlotPreset: String, CaseIterable, Identifiable {
    case morning = "Morning"
    case workHours = "Work Hours"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case night = "Night"
    case lateNight = "Late Night"
    
    var id: String { rawValue }
    
    var name: String { rawValue }
    
    var startHour: Int {
        switch self {
        case .morning: return 6
        case .workHours: return 9
        case .afternoon: return 12
        case .evening: return 17
        case .night: return 21
        case .lateNight: return 0
        }
    }
    
    var endHour: Int {
        switch self {
        case .morning: return 12
        case .workHours: return 17
        case .afternoon: return 17
        case .evening: return 21
        case .night: return 24
        case .lateNight: return 6
        }
    }
    
    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .workHours: return "briefcase.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.fill"
        case .lateNight: return "moon.stars.fill"
        }
    }
    
    var timeLabel: String {
        let startStr = formatHour(startHour)
        let endStr = formatHour(endHour == 24 ? 0 : endHour)
        return "\(startStr) – \(endStr)"
    }
    
    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 || hour == 24 ? "AM" : "PM"
        return "\(h12)\(ampm)"
    }
}

// MARK: - Duration Presets

enum DurationPreset: CaseIterable {
    case any
    case quick       // < 1 min
    case short       // < 5 min
    case medium      // 5-30 min
    case long        // 30min - 1hr
    case extended    // > 1 hr
    
    var name: String {
        switch self {
        case .any: return "Any"
        case .quick: return "< 1m"
        case .short: return "< 5m"
        case .medium: return "5-30m"
        case .long: return "30m-1h"
        case .extended: return "> 1h"
        }
    }
    
    var minSeconds: Double? {
        switch self {
        case .any: return nil
        case .quick: return nil
        case .short: return nil
        case .medium: return 300
        case .long: return 1800
        case .extended: return 3600
        }
    }
    
    var maxSeconds: Double? {
        switch self {
        case .any: return nil
        case .quick: return 60
        case .short: return 300
        case .medium: return 1800
        case .long: return 3600
        case .extended: return nil
        }
    }
}
