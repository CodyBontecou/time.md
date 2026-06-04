import AppKit
import Foundation

/// Resolves bundle identifiers to real app display names and icons via NSWorkspace.
/// Results are cached in memory for the lifetime of the app.
@MainActor
final class AppIconProvider {

    static let shared = AppIconProvider()

    private var nameCache: [String: String] = [:]
    private var iconCache: [String: NSImage] = [:]
    private var missingIconCache: Set<String> = []

    private init() {}

    // MARK: - Display Name

    /// Returns a previously-resolved display name without touching LaunchServices.
    /// Use from SwiftUI body/chart code to avoid synchronous NSWorkspace stalls.
    func cachedDisplayName(for bundleID: String) -> String? {
        nameCache[bundleID]
    }

    /// Returns the real display name for a bundle identifier (e.g. "com.apple.Safari" → "Safari").
    /// Falls back to the last component of the bundle ID if the app can't be found.
    func displayName(for bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }

        let resolved = resolveName(bundleID)
        nameCache[bundleID] = resolved
        return resolved
    }

    /// Returns a previously-resolved icon without touching LaunchServices.
    /// Use from SwiftUI body code to avoid doing app discovery during layout.
    func cachedIcon(for bundleID: String) -> NSImage? {
        iconCache[bundleID]
    }

    /// Returns the app icon for a bundle identifier, or nil if unavailable.
    func icon(for bundleID: String, size: CGFloat = 32) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        if missingIconCache.contains(bundleID) { return nil }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missingIconCache.insert(bundleID)
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        image.size = NSSize(width: size, height: size)
        iconCache[bundleID] = image
        return image
    }

    /// Warms display-name and icon caches for the small set of app IDs a screen
    /// is about to render. This keeps row/body recomputation from repeatedly
    /// touching LaunchServices when lists update or scroll.
    func preload(bundleIDs: [String], size: CGFloat = 32, limit: Int = 50) {
        var seen: Set<String> = []
        var warmed = 0
        for bundleID in bundleIDs where seen.insert(bundleID).inserted {
            guard bundleID.contains("."), bundleID != "Other", bundleID != "Unknown" else { continue }
            guard warmed < limit else { break }
            guard nameCache[bundleID] == nil || (iconCache[bundleID] == nil && !missingIconCache.contains(bundleID)) else { continue }

            warmed += 1
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                nameCache[bundleID] = nameCache[bundleID] ?? fallbackName(for: bundleID)
                missingIconCache.insert(bundleID)
                continue
            }

            if nameCache[bundleID] == nil {
                nameCache[bundleID] = resolveName(bundleID, appURL: appURL)
            }

            if iconCache[bundleID] == nil, !missingIconCache.contains(bundleID) {
                let image = NSWorkspace.shared.icon(forFile: appURL.path)
                image.size = NSSize(width: size, height: size)
                iconCache[bundleID] = image
            }
        }
    }

    /// Clears all cached data.
    func clearCache() {
        nameCache.removeAll()
        iconCache.removeAll()
        missingIconCache.removeAll()
    }

    // MARK: - Private

    private func resolveName(_ bundleID: String) -> String {
        // Not a bundle ID — return as-is
        guard bundleID.contains(".") else { return bundleID }

        // Try to find the app on disk and read its display name
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return resolveName(bundleID, appURL: appURL)
        }

        // Fallback: last component of the bundle ID
        return fallbackName(for: bundleID)
    }

    private func resolveName(_ bundleID: String, appURL: URL) -> String {
        if let bundle = Bundle(url: appURL) {
            // Prefer CFBundleDisplayName (user-facing), fall back to CFBundleName
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !bundleName.isEmpty {
                return bundleName
            }
        }
        return fallbackName(for: bundleID)
    }

    private func fallbackName(for bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
