import Foundation

enum NavigationDestination: String, CaseIterable, Identifiable {
    case overview
    case review
    case details
    case projects
    case rules
    case webHistory
    case reports
    case export
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .review: "Review"
        case .details: "Details"
        case .projects: "Projects"
        case .rules: "Rules"
        case .webHistory: "Web History"
        case .reports: "Reports"
        case .export: "Export"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "clock.fill"
        case .review: "chart.bar.fill"
        case .details: "list.bullet.rectangle.fill"
        case .projects: "folder.fill"
        case .rules: "gearshape.2.fill"
        case .webHistory: "globe"
        case .reports: "doc.text.fill"
        case .export: "square.and.arrow.up"
        case .settings: "gear"
        }
    }

    /// Sidebar section grouping
    var section: NavigationSection {
        switch self {
        case .overview: .tracking
        case .review: .tracking
        case .details: .tracking
        case .projects: .organize
        case .rules: .organize
        case .webHistory: .data
        case .reports: .data
        case .export: .data
        case .settings: .system
        }
    }

    /// Whether this destination can be exported
    var isExportable: Bool {
        switch self {
        case .overview, .review, .details, .projects, .webHistory, .reports, .export:
            return true
        case .rules, .settings:
            return false
        }
    }
}

enum NavigationSection: String, CaseIterable, Identifiable {
    case tracking = "Tracking"
    case organize = "Organize"
    case data = "Data"
    case system = "System"

    var id: String { rawValue }

    /// Sections that should be displayed in the sidebar
    static var visibleSections: [NavigationSection] {
        [.tracking, .organize, .data, .system]
    }
}
