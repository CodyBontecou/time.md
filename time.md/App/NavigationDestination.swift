import Foundation

enum NavigationDestination: String, CaseIterable, Identifiable {
    case overview
    case review
    case details
    case projects
    case rules
    case webHistory
    case input
    case reports
    case export
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .review: String(localized: "Review")
        case .details: String(localized: "Details")
        case .projects: String(localized: "Projects")
        case .rules: String(localized: "Rules")
        case .webHistory: String(localized: "Web History")
        case .input: String(localized: "Input")
        case .reports: String(localized: "Reports")
        case .export: String(localized: "Export")
        case .settings: String(localized: "Settings")
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
        case .input: "keyboard"
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
        case .input: .data
        case .reports: .data
        case .export: .data
        case .settings: .system
        }
    }

    /// Whether this destination can be exported
    var isExportable: Bool {
        switch self {
        case .overview, .review, .details, .projects, .webHistory, .input, .reports, .export:
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
