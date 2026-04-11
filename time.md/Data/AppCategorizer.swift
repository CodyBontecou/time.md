import AppKit
import Foundation
import SQLite3

/// Automatically categorizes apps by reading `LSApplicationCategoryType` from
/// their bundle's Info.plist via NSWorkspace. Populates `CategoryMappingStore`
/// for any tracked app that doesn't already have a category mapping.
enum AppCategorizer {

    /// Scans the usage database for distinct app bundle IDs, checks which ones
    /// lack a category mapping, and auto-populates from the app's
    /// `LSApplicationCategoryType` plist key.
    static func autoPopulateCategories() {
        do {
            let existingMappings = try CategoryMappingStore.fetchAll()
            let mappedApps = Set(existingMappings.map(\.appName))

            let trackedApps = try fetchDistinctAppNames()
            let unmapped = trackedApps.filter { !mappedApps.contains($0) }

            guard !unmapped.isEmpty else { return }

            for bundleID in unmapped {
                guard let category = resolveCategory(for: bundleID) else { continue }
                try? CategoryMappingStore.upsert(appName: bundleID, category: category)
            }

            let categorized = unmapped.filter { resolveCategory(for: $0) != nil }.count
            if categorized > 0 {
                print("[AppCategorizer] Auto-categorized \(categorized) app(s)")
            }
        } catch {
            print("[AppCategorizer] Failed: \(error.localizedDescription)")
        }
    }

    /// Resolves a human-friendly category name from a bundle ID by reading
    /// the app's `LSApplicationCategoryType` key.
    static func resolveCategory(for bundleID: String) -> String? {
        guard bundleID.contains("."),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: appURL),
              let uti = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
              !uti.isEmpty else {
            return nil
        }

        return friendlyName(for: uti)
    }

    // MARK: - Private

    /// Queries the screentime.db for all distinct app_name values.
    private static func fetchDistinctAppNames() throws -> [String] {
        let dbURL = try HistoryStore.databaseURL()
        var handle: OpaquePointer?

        guard sqlite3_open_v2(
            dbURL.path, &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil
        ) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            return []
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT DISTINCT app_name FROM usage"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(statement, 0) {
                names.append(String(cString: cStr))
            }
        }
        return names
    }

    /// Maps Apple's `LSApplicationCategoryType` UTI strings to human-friendly names.
    private static func friendlyName(for uti: String) -> String? {
        utiToFriendlyName[uti.lowercased()]
    }

    private static let utiToFriendlyName: [String: String] = [
        // Business
        "public.app-category.business": "Business",

        // Developer Tools
        "public.app-category.developer-tools": "Developer Tools",

        // Education
        "public.app-category.education": "Education",

        // Entertainment
        "public.app-category.entertainment": "Entertainment",

        // Finance
        "public.app-category.finance": "Finance",

        // Games
        "public.app-category.games": "Games",
        "public.app-category.action-games": "Games",
        "public.app-category.adventure-games": "Games",
        "public.app-category.arcade-games": "Games",
        "public.app-category.board-games": "Games",
        "public.app-category.card-games": "Games",
        "public.app-category.casino-games": "Games",
        "public.app-category.dice-games": "Games",
        "public.app-category.educational-games": "Games",
        "public.app-category.family-games": "Games",
        "public.app-category.kids-games": "Games",
        "public.app-category.music-games": "Games",
        "public.app-category.puzzle-games": "Games",
        "public.app-category.racing-games": "Games",
        "public.app-category.role-playing-games": "Games",
        "public.app-category.simulation-games": "Games",
        "public.app-category.sports-games": "Games",
        "public.app-category.strategy-games": "Games",
        "public.app-category.trivia-games": "Games",
        "public.app-category.word-games": "Games",

        // Graphics & Design
        "public.app-category.graphics-design": "Graphics & Design",

        // Health & Fitness
        "public.app-category.healthcare-fitness": "Health & Fitness",

        // Lifestyle
        "public.app-category.lifestyle": "Lifestyle",

        // Medical
        "public.app-category.medical": "Medical",

        // Music
        "public.app-category.music": "Music",

        // News
        "public.app-category.news": "News",

        // Photography
        "public.app-category.photography": "Photography",

        // Productivity
        "public.app-category.productivity": "Productivity",

        // Reference
        "public.app-category.reference": "Reference",

        // Social Networking
        "public.app-category.social-networking": "Social Networking",

        // Sports
        "public.app-category.sports": "Sports",

        // Travel
        "public.app-category.travel": "Travel",

        // Utilities
        "public.app-category.utilities": "Utilities",

        // Video
        "public.app-category.video": "Video",

        // Weather
        "public.app-category.weather": "Weather",
    ]
}
