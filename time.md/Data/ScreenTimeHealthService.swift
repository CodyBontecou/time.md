import Foundation
import SQLite3

/// Health status of the macOS Screen Time data source.
enum ScreenTimeHealthStatus: Equatable, Sendable {
    /// Screen Time data is being recorded normally.
    case healthy
    
    /// Screen Time data hasn't been updated recently.
    /// - Parameters:
    ///   - lastRecordDate: When the last usage record was recorded
    ///   - hoursStale: How many hours since the last record
    case stale(lastRecordDate: Date, hoursStale: Int)
    
    /// No Screen Time data exists at all.
    case noData
    
    /// Could not check health status (e.g., database access error).
    case unknown(reason: String)
    
    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
    
    var needsAttention: Bool {
        switch self {
        case .healthy, .unknown: return false
        case .stale, .noData: return true
        }
    }
}

/// Service that checks the health of macOS Screen Time data collection.
///
/// Detects when Apple's knowledgeC.db has stopped receiving new app usage data,
/// which can happen when:
/// - Screen Time is disabled in System Settings
/// - The knowledged daemon has crashed or stopped
/// - A macOS bug is preventing data collection
enum ScreenTimeHealthService {
    private static let appleEpochOffset: Double = 978_307_200
    
    /// Threshold in hours before data is considered stale.
    /// 4 hours allows for normal gaps (sleep, away from computer)
    /// while catching genuine issues.
    private static let staleThresholdHours: Int = 4
    
    // MARK: - Public
    
    /// Check the health of Screen Time data collection.
    /// - Returns: Current health status of the Screen Time system.
    static func checkHealth() -> ScreenTimeHealthStatus {
        let knowledgePath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
        
        guard FileManager.default.fileExists(atPath: knowledgePath.path) else {
            return .noData
        }
        
        // Open knowledgeC.db read-only
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            knowledgePath.path, &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil
        )
        
        guard result == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            return .unknown(reason: "Could not open Screen Time database")
        }
        defer { sqlite3_close(db) }
        
        // Check for the most recent app usage record
        let sql = """
        SELECT MAX(ZSTARTDATE) FROM ZOBJECT
        WHERE ZSTREAMNAME = '/app/usage'
          AND ZVALUESTRING IS NOT NULL
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return .unknown(reason: "Could not query Screen Time database")
        }
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .noData
        }
        
        // Check if the result is NULL (no records)
        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return .noData
        }
        
        let appleTimestamp = sqlite3_column_double(statement, 0)
        let lastRecordDate = Date(timeIntervalSince1970: appleTimestamp + appleEpochOffset)
        
        let hoursSinceLastRecord = Int(Date().timeIntervalSince(lastRecordDate) / 3600)
        
        if hoursSinceLastRecord >= staleThresholdHours {
            return .stale(lastRecordDate: lastRecordDate, hoursStale: hoursSinceLastRecord)
        }
        
        return .healthy
    }
    
    /// Async wrapper for checking health status.
    static func checkHealthAsync() async -> ScreenTimeHealthStatus {
        await Task.detached(priority: .utility) {
            checkHealth()
        }.value
    }
}
