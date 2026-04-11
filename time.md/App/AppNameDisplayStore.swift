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
/// When the mode is `.short`, uses `AppIconProvider` to resolve the real app name
/// (e.g. `com.apple.Safari` → "Safari", `com.google.Chrome` → "Google Chrome").
/// Falls back to the last bundle-ID component when the app isn't installed.
/// Identifiers that don't look like bundle IDs are returned as-is in both modes.
enum AppNameDisplay {
    @MainActor
    static func displayName(for rawName: String, mode: AppNameDisplayMode) -> String {
        guard mode == .short else { return rawName }

        // Keep special names untouched
        if rawName == "Other" || rawName == "Unknown" { return rawName }

        // Only transform dotted reverse-DNS identifiers
        guard rawName.contains(".") else { return rawName }

        #if os(macOS)
        return AppIconProvider.shared.displayName(for: rawName)
        #else
        let lastComponent = rawName.split(separator: ".").last.map(String.init) ?? rawName
        guard !lastComponent.isEmpty, lastComponent != rawName else { return rawName }
        return lastComponent
        #endif
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
