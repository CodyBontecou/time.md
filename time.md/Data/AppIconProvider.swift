import AppKit
import Foundation

/// Resolves bundle identifiers to real app display names and icons via NSWorkspace.
/// Results are cached in memory for the lifetime of the app.
@MainActor
final class AppIconProvider {

    static let shared = AppIconProvider()

    private var nameCache: [String: String] = [:]
    private var iconCache: [String: NSImage] = [:]

    private init() {}

    // MARK: - Display Name

    /// Returns the real display name for a bundle identifier (e.g. "com.apple.Safari" → "Safari").
    /// Falls back to the last component of the bundle ID if the app can't be found.
    func displayName(for bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }

        let resolved = resolveName(bundleID)
        nameCache[bundleID] = resolved
        return resolved
    }

    /// Returns the app icon for a bundle identifier, or nil if unavailable.
    func icon(for bundleID: String, size: CGFloat = 32) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        image.size = NSSize(width: size, height: size)
        iconCache[bundleID] = image
        return image
    }

    /// Clears all cached data.
    func clearCache() {
        nameCache.removeAll()
        iconCache.removeAll()
    }

    // MARK: - Private

    private func resolveName(_ bundleID: String) -> String {
        // Not a bundle ID — return as-is
        guard bundleID.contains(".") else { return bundleID }

        // Try to find the app on disk and read its display name
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: appURL) {
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

        // Fallback: last component of the bundle ID
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
