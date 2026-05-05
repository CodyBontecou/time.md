import AppKit
import Carbon.HIToolbox
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

    // Web tab tracking state (browsers only).
    private var webURL: String?
    private var webDomain: String?
    private var webTitle: String?
    private var webStartTime: Date?
    private var webBrowserBundleID: String?
    private var webPollTimer: DispatchSourceTimer?
    private let webPollInterval: TimeInterval = 30.0

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Posted on the main queue after a session is written to the database.
    static let didRecordSessionNotification = Notification.Name("ActiveAppTrackerDidRecordSession")

    /// Lightweight snapshot used by `InputEventTracker` to attribute keystroke
    /// and mouse events to whatever app was frontmost at flush time.
    struct CurrentAppSnapshot: Sendable {
        let bundleID: String?
        let switchTime: Date?
        let secureInput: Bool
        let isScreenActive: Bool
    }

    /// Returns the active app and secure-input state at the moment of the call.
    /// Reads under the existing lock so the result is consistent with whatever
    /// `handleAppSwitch` last committed. Thread-safe.
    func snapshot() -> CurrentAppSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return CurrentAppSnapshot(
            bundleID: currentApp,
            switchTime: switchTime,
            secureInput: IsSecureEventInputEnabled(),
            isScreenActive: isScreenActive
        )
    }

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
                if BrowserTabSampler.isSupportedBrowser(bundleID: appID) {
                    startWebPolling(for: appID)
                }
            }
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        finalizeCurrentSession()
        finalizeCurrentWebSession()
        stopWebPolling()
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
        finalizeCurrentWebSession()

        currentApp = newApp
        switchTime = Date()

        if let bundleID = newApp,
           BrowserTabSampler.isSupportedBrowser(bundleID: bundleID) {
            startWebPolling(for: bundleID)
        } else {
            stopWebPolling()
        }

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
        finalizeCurrentWebSession()
        stopWebPolling()
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

    // MARK: - Web Tab Sampling (must be called under lock except where noted)

    /// Begins polling the active tab for the given browser. Samples immediately,
    /// then every `webPollInterval` seconds until `stopWebPolling` is called.
    private func startWebPolling(for bundleID: String) {
        webBrowserBundleID = bundleID

        // Sample once immediately (off the lock to avoid blocking on AppleScript).
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.sampleAndUpdateTab()
        }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + webPollInterval, repeating: webPollInterval)
        timer.setEventHandler { [weak self] in
            self?.sampleAndUpdateTab()
        }
        webPollTimer?.cancel()
        webPollTimer = timer
        timer.resume()
    }

    private func stopWebPolling() {
        webPollTimer?.cancel()
        webPollTimer = nil
        webBrowserBundleID = nil
    }

    /// Off-lock entry point used by the timer. Acquires the lock to mutate state.
    private func sampleAndUpdateTab() {
        lock.lock()
        let bundleID = webBrowserBundleID
        lock.unlock()

        guard let bundleID,
              let browser = BrowserTabSampler.browser(for: bundleID),
              let tab = BrowserTabSampler.currentTab(for: browser)
        else { return }

        lock.lock()
        defer { lock.unlock() }

        // Browser may have changed underneath us during the AppleScript call.
        guard webBrowserBundleID == bundleID, isScreenActive else { return }

        if tab.url == webURL { return }

        finalizeCurrentWebSession()
        webURL = tab.url
        webDomain = tab.domain
        webTitle = tab.title
        webStartTime = Date()
    }

    /// Closes out the current web session, if any, and writes it to the DB.
    /// Must be called under `lock`.
    private func finalizeCurrentWebSession() {
        guard let domain = webDomain,
              let start = webStartTime else {
            webURL = nil
            webDomain = nil
            webTitle = nil
            webStartTime = nil
            return
        }

        let duration = Date().timeIntervalSince(start)
        let url = webURL
        let title = webTitle
        webURL = nil
        webDomain = nil
        webTitle = nil
        webStartTime = nil

        guard duration >= minimumSessionDuration else { return }

        let startISO = dateFormatter.string(from: start)
        let sourceTimestamp = start.timeIntervalSince1970
        let deviceId = DeviceInfo.current().id

        DispatchQueue.global(qos: .utility).async {
            Self.writeWebSession(
                domain: domain,
                url: url,
                title: title,
                startTime: startISO,
                durationSeconds: duration,
                sourceTimestamp: sourceTimestamp,
                deviceId: deviceId
            )
        }
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

    private static func writeWebSession(
        domain: String,
        url: String?,
        title: String?,
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
                print("[ActiveAppTracker] Failed to open database (web)")
                return
            }
            defer { sqlite3_close(db) }

            sqlite3_busy_timeout(db, 5000)

            let sql = """
            INSERT OR IGNORE INTO usage
                (app_name, duration_seconds, start_time, stream_type,
                 source_timestamp, device_id, metadata_hash, url, title)
            VALUES (?, ?, ?, 'web_usage', ?, ?, 'direct_observation', ?, ?)
            """

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let statement = stmt else {
                print("[ActiveAppTracker] Web prepare failed: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, domain, -1, transient)
            sqlite3_bind_double(statement, 2, durationSeconds)
            sqlite3_bind_text(statement, 3, startTime, -1, transient)
            sqlite3_bind_double(statement, 4, sourceTimestamp)
            sqlite3_bind_text(statement, 5, deviceId, -1, transient)
            if let url { sqlite3_bind_text(statement, 6, url, -1, transient) }
            else { sqlite3_bind_null(statement, 6) }
            if let title { sqlite3_bind_text(statement, 7, title, -1, transient) }
            else { sqlite3_bind_null(statement, 7) }

            let result = sqlite3_step(statement)
            if result != SQLITE_DONE {
                print("[ActiveAppTracker] Web insert failed: \(String(cString: sqlite3_errmsg(db)))")
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: ActiveAppTracker.didRecordSessionNotification, object: nil)
                }
            }
        } catch {
            print("[ActiveAppTracker] Web error: \(error.localizedDescription)")
        }
    }
}
