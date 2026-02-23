import Foundation

enum NavigationDestination: String, CaseIterable, Identifiable {
    case overview
    case appsCategories
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .appsCategories: "Apps & Categories"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .appsCategories: "chart.bar.doc.horizontal"
        case .settings: "gear"
        }
    }
}
