import Foundation

// MARK: - Browser source

enum BrowserSource: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case safari = "Safari"
    case chrome = "Chrome"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "globe"
        case .safari: return "safari"
        case .chrome: return "globe.americas"
        }
    }
}

// MARK: - Visit entry

struct BrowsingVisit: Identifiable, Sendable {
    let id: String          // unique composite key
    let url: String
    let title: String
    let domain: String
    let visitTime: Date
    let durationSeconds: Double?   // Chrome only; nil for Safari
    let browser: BrowserSource
}

// MARK: - Domain summary

struct DomainSummary: Identifiable, Sendable {
    var id: String { domain }
    let domain: String
    let visitCount: Int
    let totalDurationSeconds: Double?
    let lastVisitTime: Date
}

// MARK: - Daily visit count for trend chart

struct DailyVisitCount: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let visitCount: Int
}

// MARK: - Hourly visit count for heatmap-style chart

struct HourlyVisitCount: Identifiable, Sendable {
    var id: Int { hour }
    let hour: Int       // 0–23
    let visitCount: Int
}
