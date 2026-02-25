import Foundation

/// Shared time and date formatting utilities for time.md
enum TimeFormatters {
    
    // MARK: - Duration Formatting
    
    /// Format seconds as "Xh Ym" or "Xm" for shorter durations
    static func formatDuration(_ seconds: Double, style: DurationStyle = .compact) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        switch style {
        case .compact:
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(minutes)m"
            
        case .full:
            if hours > 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) min"
            }
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
            
        case .hoursOnly:
            let decimalHours = seconds / 3600
            return String(format: "%.1fh", decimalHours)
            
        case .minutesOnly:
            return "\(totalMinutes)m"
        }
    }
    
    enum DurationStyle {
        case compact    // "2h 30m"
        case full       // "2 hours 30 minutes"
        case hoursOnly  // "2.5h"
        case minutesOnly // "150m"
    }
    
    /// Format seconds as hours with one decimal place
    static func formatHours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        return String(format: "%.1f", hours)
    }
    
    /// Format seconds for display in charts (abbreviated)
    static func formatChartValue(_ seconds: Double) -> String {
        if seconds >= 3600 {
            return String(format: "%.1fh", seconds / 3600)
        } else if seconds >= 60 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds))s"
    }
    
    // MARK: - Date Formatting
    
    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private static let isoDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()
    
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    private static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
    
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    /// ISO date string (2026-02-23)
    static func isoDate(_ date: Date) -> String {
        isoDateFormatter.string(from: date)
    }
    
    /// ISO datetime string with timezone
    static func isoDateTime(_ date: Date) -> String {
        isoDateTimeFormatter.string(from: date)
    }
    
    /// Short date (2/23/26)
    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }
    
    /// Medium date (Feb 23, 2026)
    static func mediumDate(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }
    
    /// Day of week (Mon, Tue, etc.)
    static func dayOfWeek(_ date: Date) -> String {
        dayOfWeekFormatter.string(from: date)
    }
    
    /// Month and day (Feb 23)
    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }
    
    /// Format date range (Feb 17 – Feb 23)
    static func dateRange(from startDate: Date, to endDate: Date) -> String {
        let start = monthDay(startDate)
        let end = monthDay(endDate)
        return "\(start) – \(end)"
    }
    
    // MARK: - Relative Time
    
    /// Relative time string ("Today", "Yesterday", "3 days ago")
    static func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        let components = calendar.dateComponents([.day], from: date, to: now)
        if let days = components.day, days < 7 {
            return "\(days) days ago"
        }
        
        return mediumDate(date)
    }
    
    // MARK: - Hour Formatting
    
    /// Format hour (0-23) as "12 AM", "3 PM", etc.
    static func formatHour(_ hour: Int) -> String {
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour) \(period)"
    }
    
    /// Format hour range (0-23) as "12–1 AM", "3–4 PM", etc.
    static func formatHourRange(_ hour: Int) -> String {
        let nextHour = (hour + 1) % 24
        let period = nextHour <= 12 || nextHour == 0 ? (hour < 12 ? "AM" : "PM") : "PM"
        
        let displayStart = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let displayEnd = nextHour == 0 ? 12 : (nextHour > 12 ? nextHour - 12 : nextHour)
        
        return "\(displayStart)–\(displayEnd) \(period)"
    }
    
    // MARK: - Weekday Formatting
    
    /// Weekday names indexed 0–6 (Sunday first)
    static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    /// Full weekday names
    static let weekdayFullNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    /// Format weekday index as name
    static func formatWeekday(_ weekday: Int) -> String {
        guard weekday >= 0 && weekday < weekdayNames.count else { return "?" }
        return weekdayNames[weekday]
    }
}

// MARK: - Percentage Formatting

extension TimeFormatters {
    /// Format as percentage with sign (+12%, -5%)
    static func formatPercentChange(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value))%"
    }
    
    /// Format as simple percentage (12%)
    static func formatPercent(_ value: Double) -> String {
        "\(Int(value))%"
    }
}
