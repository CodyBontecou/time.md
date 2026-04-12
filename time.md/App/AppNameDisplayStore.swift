import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum AppNameDisplayMode: String, CaseIterable, Identifiable {
    case short      // "Safari" (last component of bundle ID)
    case full       // "com.apple.Safari" (raw bundle identifier)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: String(localized: "SHORT NAME")
        case .full: String(localized: "BUNDLE IDENTIFIER")
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

    /// Thread-safe, nonisolated resolver for use from background export tasks.
    /// Returns the user-facing app name for a raw identifier, with an internal
    /// lock-protected cache. Safe to call from any actor or thread.
    static func resolvedName(for rawName: String) -> String {
        if rawName == "Other" || rawName == "Unknown" { return rawName }
        guard rawName.contains(".") else { return rawName }

        #if os(macOS)
        return ExportAppNameCache.shared.name(for: rawName)
        #else
        let lastComponent = rawName.split(separator: ".").last.map(String.init) ?? rawName
        guard !lastComponent.isEmpty, lastComponent != rawName else { return rawName }
        return lastComponent
        #endif
    }
}

#if os(macOS)
private final class ExportAppNameCache: @unchecked Sendable {
    static let shared = ExportAppNameCache()

    private var cache: [String: String] = [:]
    private let lock = NSLock()

    func name(for bundleID: String) -> String {
        lock.lock()
        if let cached = cache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolve(bundleID)

        lock.lock()
        cache[bundleID] = resolved
        lock.unlock()
        return resolved
    }

    private func resolve(_ bundleID: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: appURL) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !bundleName.isEmpty {
                return bundleName
            }
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
#endif

// MARK: - View Helper

/// A small text view that reads the display mode from the environment automatically.
struct AppNameText: View {
    let rawName: String
    @Environment(\.appNameDisplayMode) private var mode

    init(_ rawName: String) {
        self.rawName = rawName
    }

    var body: some View {
        Text(verbatim: AppNameDisplay.displayName(for: rawName, mode: mode))
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
