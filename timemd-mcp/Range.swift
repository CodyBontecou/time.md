import Foundation

enum DateRange {
    /// Parses a date range specifier like "7d", "30d", "today", "yesterday",
    /// "this_week", "this_month", "this_year", or an explicit ISO-8601 date
    /// ("2026-04-12" or "2026-04-12T00:00:00"). Returns a half-open
    /// [start, end) pair formatted as the `usage.start_time` ISO strings
    /// stored in screentime.db (`yyyy-MM-dd'T'HH:mm:ss`, local time).
    static func parse(since: String?, until: String? = nil) throws -> (start: String, end: String) {
        let calendar = Calendar.current
        let now = Date()
        let endDate: Date
        let startDate: Date

        if let until = until, let parsed = parseDate(until) {
            endDate = parsed
        } else {
            endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        }

        let trimmed = (since ?? "7d").trimmingCharacters(in: .whitespaces).lowercased()
        switch trimmed {
        case "today":
            startDate = calendar.startOfDay(for: now)
        case "yesterday":
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            startDate = calendar.startOfDay(for: yesterday)
        case "this_week":
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case "this_month":
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case "this_year":
            startDate = calendar.dateInterval(of: .year, for: now)?.start ?? now
        case "all":
            startDate = Date(timeIntervalSince1970: 0)
        default:
            if let suffix = trimmed.last, suffix == "d" || suffix == "w" || suffix == "m" || suffix == "y",
               let n = Int(trimmed.dropLast()) {
                let component: Calendar.Component
                switch suffix {
                case "d": component = .day
                case "w": component = .weekOfYear
                case "m": component = .month
                case "y": component = .year
                default: component = .day
                }
                startDate = calendar.date(byAdding: component, value: -n, to: now) ?? now
            } else if let parsed = parseDate(trimmed) {
                startDate = parsed
            } else {
                startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            }
        }

        return (format(startDate), format(endDate))
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }

    static func parseDate(_ input: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd"
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in formats {
            f.dateFormat = format
            if let d = f.date(from: input) { return d }
        }
        return nil
    }
}
