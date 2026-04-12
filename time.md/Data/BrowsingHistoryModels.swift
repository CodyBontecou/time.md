import Foundation

// MARK: - Browser source

enum BrowserSource: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case safari = "Safari"
    case chrome = "Chrome"
    case arc = "Arc"
    case brave = "Brave"
    case edge = "Edge"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return String(localized: "All")
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave"
        case .edge: return "Edge"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "globe"
        case .safari: return "safari"
        case .chrome: return "globe.americas"
        case .arc: return "circle.hexagongrid"
        case .brave: return "shield.lefthalf.filled"
        case .edge: return "e.circle"
        }
    }
    
    /// Whether this browser uses Chromium's history schema
    var isChromiumBased: Bool {
        switch self {
        case .chrome, .arc, .brave, .edge: return true
        case .safari, .all: return false
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

// MARK: - Page visit within a domain (for drill-down view)

struct PageVisit: Identifiable, Sendable {
    let id: String
    let url: String
    let path: String           // URL path (e.g., "/docs/api")
    let title: String
    let visitTime: Date
    let durationSeconds: Double?
    let browser: BrowserSource
}

// MARK: - Page summary for domain drill-down

struct PageSummary: Identifiable, Sendable {
    var id: String { path }
    let path: String           // URL path (e.g., "/docs/api")
    let title: String          // Most recent title for this path
    let visitCount: Int
    let visits: [PageVisit]    // All visits to this path, sorted by time desc
    let lastVisitTime: Date
    let totalDurationSeconds: Double?
}
