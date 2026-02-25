import Foundation
import SwiftUI

enum AppNameDisplayMode: String, CaseIterable, Identifiable {
    case short      // "Safari" (last component of bundle ID)
    case full       // "com.apple.Safari" (raw bundle identifier)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: "SHORT NAME"
        case .full: "BUNDLE IDENTIFIER"
        }
    }

    var description: String {
        switch self {
        case .short: "Safari"
        case .full: "com.apple.Safari"
        }
    }
}

/// Resolves a raw app identifier (often a reverse-DNS bundle ID) to a display-friendly name.
///
/// When the mode is `.short`, a bundle ID like `com.apple.Safari` becomes `Safari`.
/// Identifiers that don't look like bundle IDs are returned as-is in both modes.
enum AppNameDisplay {
    static func displayName(for rawName: String, mode: AppNameDisplayMode) -> String {
        guard mode == .short else { return rawName }

        // Keep special names untouched
        if rawName == "Other" || rawName == "Unknown" { return rawName }

        // Only transform dotted reverse-DNS identifiers
        guard rawName.contains(".") else { return rawName }

        let lastComponent = rawName.split(separator: ".").last.map(String.init) ?? rawName

        // If the last component is empty or the same as the full string, return as-is
        guard !lastComponent.isEmpty, lastComponent != rawName else { return rawName }

        return lastComponent
    }
}

// MARK: - View Helper

/// A small text view that reads the display mode from the environment automatically.
struct AppNameText: View {
    let rawName: String
    @Environment(\.appNameDisplayMode) private var mode

    init(_ rawName: String) {
        self.rawName = rawName
    }

    var body: some View {
        Text(AppNameDisplay.displayName(for: rawName, mode: mode))
    }
}

// MARK: - Environment

private struct AppNameDisplayModeKey: EnvironmentKey {
    static var defaultValue: AppNameDisplayMode = .short
}

extension EnvironmentValues {
    var appNameDisplayMode: AppNameDisplayMode {
        get { self[AppNameDisplayModeKey.self] }
        set { self[AppNameDisplayModeKey.self] = newValue }
    }
}
