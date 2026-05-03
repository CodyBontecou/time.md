import Foundation

/// Helpers for persisting access to user-selected directories across launches
/// inside the macOS sandbox. Stores a security-scoped bookmark and resolves it
/// on demand, refreshing the bookmark data if the system marks it stale.
enum SecurityScopedBookmark {
    /// Create bookmark data for a directory the user just chose via NSOpenPanel/fileImporter.
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a previously stored bookmark. Returns the live URL plus refreshed
    /// bookmark data if the OS reported the original as stale (caller should persist it).
    static func resolve(_ data: Data) throws -> (url: URL, refreshedData: Data?) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let refreshed = isStale ? try? makeBookmark(for: url) : nil
        return (url, refreshed)
    }

    /// Run `work` with the security scope started for `url`. Always stops accessing,
    /// even if `work` throws.
    static func withAccess<T>(to url: URL, _ work: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try work()
    }
}
