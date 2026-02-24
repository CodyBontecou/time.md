import Foundation

enum NavigationDestination: String, CaseIterable, Identifiable {
    case overview
    case calendar
    case trends
    case appsCategories
    case sessions
    case heatmap
    case focus
    case rawSessions   // Export-only: individual session records
    case webHistory
    case exports
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .calendar: "Calendar"
        case .trends: "Trends"
        case .appsCategories: "Apps & Categories"
        case .sessions: "Sessions"
        case .heatmap: "Heatmap"
        case .focus: "Focus & Streaks"
        case .rawSessions: "Raw Sessions"
        case .webHistory: "Web History"
        case .exports: "Exports"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .calendar: "calendar"
        case .trends: "chart.xyaxis.line"
        case .appsCategories: "chart.bar.doc.horizontal"
        case .sessions: "timer"
        case .heatmap: "square.grid.3x3.fill"
        case .focus: "flame.fill"
        case .rawSessions: "list.bullet.rectangle"
        case .webHistory: "globe"
        case .exports: "square.and.arrow.up"
        case .settings: "gear"
        }
    }

    /// Sidebar section grouping
    var section: NavigationSection {
        switch self {
        case .overview: .analytics
        case .calendar: .analytics
        case .trends: .analytics
        case .appsCategories: .analytics
        case .sessions: .analytics
        case .heatmap: .analytics
        case .focus: .analytics
        case .rawSessions: .hidden  // Not shown in sidebar, only in export scope
        case .webHistory: .data
        case .exports: .data
        case .settings: .system
        }
    }

    /// Whether this destination can be exported
    var isExportable: Bool {
        switch self {
        case .overview, .calendar, .appsCategories, .trends, .sessions, .heatmap, .focus, .rawSessions:
            return true
        case .webHistory, .exports, .settings:
            return false
        }
    }
}

enum NavigationSection: String, CaseIterable, Identifiable {
    case analytics = "Analytics"
    case data = "Data"
    case system = "System"
    case hidden = "Hidden"  // Not displayed in sidebar

    var id: String { rawValue }

    /// Sections that should be displayed in the sidebar
    static var visibleSections: [NavigationSection] {
        [.analytics, .data, .system]
    }
}
