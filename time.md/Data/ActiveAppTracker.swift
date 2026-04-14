import AppKit
import Foundation
import SQLite3

/// Observes real-time app switches via NSWorkspace and writes usage records
/// directly to the screentime.db `usage` table, providing reliable tracking
/// independent of Apple's knowledgeC.db.
final class ActiveAppTracker: @unchecked Sendable {

    static let shared = ActiveAppTracker()

    private let lock = NSLock()
    private var currentApp: String?
    private var switchTime: Date?
    private var isScreenActive = true
    private var observers: [NSObjectProtocol] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Posted on the main queue after a session is written to the database.
    static let didRecordSessionNotification = Notification.Name("ActiveAppTrackerDidRecordSession")

    /// Sessions shorter than this are discarded (filters Cmd-Tab fly-throughs).
    private let minimumSessionDuration: TimeInterval = 2.0

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Bundle IDs already checked for category mapping this session.
    private var categorizedApps: Set<String> = []

    private init() {}

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard observers.isEmpty else { return }

        let nc = NSWorkspace.shared.notificationCenter

        observers.append(nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.handleAppSwitch(to: app)
        })

        observers.append(nc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleScreenInactive() })

        observers.append(nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleScreenActive() })

        observers.append(nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleScreenInactive() })

        observers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleScreenActive() })

        observers.append(nc.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleScreenInactive() })

        observers.append(nc.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.handleScreenActive() })

        // Seed with current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            currentApp = frontmost.bundleIdentifier ?? frontmost.localizedName
            switchTime = Date()
            isScreenActive = true
            if let appID = currentApp {
                let ts = switchTime!.timeIntervalSince1970
                DispatchQueue.global(qos: .utility).async {
                    Self.writeCurrentSessionFile(appName: appID, startTimestamp: ts)
                }
            }
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        finalizeCurrentSession()
        DispatchQueue.global(qos: .utility).async {
            Self.clearCurrentSessionFile()
        }

        let nc = NSWorkspace.shared.notificationCenter
        for observer in observers {
            nc.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Event Handlers

    private func handleAppSwitch(to app: NSRunningApplication) {
        lock.lock()
        defer { lock.unlock() }

        guard isScreenActive else { return }

        let newApp = app.bundleIdentifier ?? app.localizedName
        guard newApp != currentApp else { return }

        finalizeCurrentSession()

        currentApp = newApp
        switchTime = Date()

        if let appID = newApp {
            let ts = switchTime!.timeIntervalSince1970
            DispatchQueue.global(qos: .utility).async {
                Self.writeCurrentSessionFile(appName: appID, startTimestamp: ts)
            }
        }

        // Auto-categorize newly seen apps on first switch
        if let appID = newApp, !categorizedApps.contains(appID) {
            categorizedApps.insert(appID)
            DispatchQueue.global(qos: .utility).async {
                if let category = AppCategorizer.resolveCategory(for: appID) {
                    try? CategoryMappingStore.upsert(appName: appID, category: category)
                }
            }
        }
    }

    private func handleScreenInactive() {
        lock.lock()
        defer { lock.unlock() }

        guard isScreenActive else { return }
        isScreenActive = false
        finalizeCurrentSession()
        DispatchQueue.global(qos: .utility).async {
            Self.clearCurrentSessionFile()
        }
    }

    private func handleScreenActive() {
        lock.lock()
        defer { lock.unlock() }

        guard !isScreenActive else { return }
        isScreenActive = true

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            currentApp = frontmost.bundleIdentifier ?? frontmost.localizedName
            switchTime = Date()
        }
    }

    // MARK: - Session Finalization (must be called under lock)

    private func finalizeCurrentSession() {
        guard let appName = currentApp,
              let start = switchTime else {
            currentApp = nil
            switchTime = nil
            return
        }

        let duration = Date().timeIntervalSince(start)

        currentApp = nil
        switchTime = nil

        guard duration >= minimumSessionDuration else { return }

        let startISO = dateFormatter.string(from: start)
        let sourceTimestamp = start.timeIntervalSince1970
        let deviceId = DeviceInfo.current().id

        DispatchQueue.global(qos: .utility).async {
            Self.writeSession(
                appName: appName,
                startTime: startISO,
                durationSeconds: duration,
                sourceTimestamp: sourceTimestamp,
                deviceId: deviceId
            )
        }
    }

    // MARK: - Current Session Hint File

    private static var currentSessionURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/time.md/current_session.json")
    }

    private static func writeCurrentSessionFile(appName: String, startTimestamp: Double) {
        let dict: [String: Any] = [
            "app_name": appName,
            "start_timestamp": startTimestamp,
            "stream_type": "app_usage"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: currentSessionURL, options: .atomic)
    }

    private static func clearCurrentSessionFile() {
        try? FileManager.default.removeItem(at: currentSessionURL)
    }

    // MARK: - Database Write

    private static func writeSession(
        appName: String,
        startTime: String,
        durationSeconds: Double,
        sourceTimestamp: Double,
        deviceId: String
    ) {
        do {
            let dbURL = try HistoryStore.databaseURL()
            var handle: OpaquePointer?

            guard sqlite3_open_v2(
                dbURL.path, &handle,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
            ) == SQLITE_OK, let db = handle else {
                if let handle { sqlite3_close(handle) }
                print("[ActiveAppTracker] Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            sqlite3_busy_timeout(db, 5000)

            let sql = """
            INSERT OR IGNORE INTO usage
                (app_name, duration_seconds, start_time, stream_type,
                 source_timestamp, device_id, metadata_hash)
            VALUES (?, ?, ?, 'app_usage', ?, ?, 'direct_observation')
            """

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                print("[ActiveAppTracker] Prepare failed: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, appName, -1, transient)
            sqlite3_bind_double(statement, 2, durationSeconds)
            sqlite3_bind_text(statement, 3, startTime, -1, transient)
            sqlite3_bind_double(statement, 4, sourceTimestamp)
            sqlite3_bind_text(statement, 5, deviceId, -1, transient)

            let result = sqlite3_step(statement)
            if result != SQLITE_DONE {
                print("[ActiveAppTracker] Insert failed: \(String(cString: sqlite3_errmsg(db)))")
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: ActiveAppTracker.didRecordSessionNotification, object: nil)
                }
            }
        } catch {
            print("[ActiveAppTracker] Error: \(error.localizedDescription)")
        }
    }
}
