import AppKit
import Carbon.HIToolbox
import Foundation
import SQLite3
import os.lock

/// Opt-in keystroke + mouse event tracker. Off by default — only starts when
/// `inputTrackingEnabled` is true and the user has granted Accessibility +
/// Input Monitoring permissions. Captures every key/mouse event globally,
/// applies privacy guards, batches into SQLite every 2 s.
///
/// **Privacy contract**
/// 1. Secure Input Mode → drop typed characters but keep the count, mark
///    `secure_input=1` on the row.
/// 2. Excluded bundle IDs (1Password, Bitwarden, etc.) → drop entire event.
/// 3. Pause hotkey ⌥⌘P → drop everything for `pauseDurationSeconds`.
/// 4. Content capture is gated by a *second* flag (`inputTrackingCaptureContent`,
///    default false) so users who only want intensity / heatmap stats never
///    accidentally turn on content recording.
final class InputEventTracker: @unchecked Sendable {

    static let shared = InputEventTracker()

    // MARK: - User defaults keys

    static let enabledKey = "inputTrackingEnabled"
    /// Legacy boolean — superseded by `keystrokeLevelKey`. Read once for
    /// migration, then ignored. Kept so old installs upgrade gracefully.
    static let captureContentKey = "inputTrackingCaptureContent"
    static let keystrokeLevelKey = "inputTrackingKeystrokeLevel"
    static let cursorLevelKey = "inputTrackingCursorLevel"
    static let exclusionListKey = "inputTrackingExclusionList"
    static let pausedUntilKey = "inputTrackingPausedUntil"

    /// Default pause duration when the user hits the hotkey.
    static let pauseDurationSeconds: TimeInterval = 30 * 60

    /// Default exclusion list. Users can add to / remove from this in Settings.
    static let defaultExclusions: Set<String> = [
        "com.1password.1password",
        "com.1password.1password7",
        "com.agilebits.onepassword4",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.dashlane.dashlane",
        "com.lastpass.LastPass",
        "com.apple.keychainaccess"
    ]

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var flushTimer: DispatchSourceTimer?
    private var hotkeyMonitor: Any?

    private var bufferLock = os_unfair_lock_s()
    private var keystrokeBuffer: [PendingKeystroke] = []
    private var mouseBuffer: [PendingMouseEvent] = []

    /// Set on the tap-installation thread, read on the flush thread.
    /// Guarded by `bufferLock`.
    private var pausedUntilTimestamp: Double = 0
    private var exclusionSet: Set<String> = defaultExclusions
    private var keystrokeLevel: KeystrokeTrackingLevel = .perKey
    private var cursorLevel: CursorTrackingLevel = .heatmap

    private init() {
        loadSettings()
    }

    // MARK: - Lifecycle

    func start() {
        guard eventTap == nil else { return }

        loadSettings()

        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown,
            .scrollWheel,
            .leftMouseDragged, .rightMouseDragged
        ]
        var mask: CGEventMask = 0
        for type in eventTypes {
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: InputEventTracker.tapCallback,
            userInfo: userInfo
        ) else {
            // Permission missing or system refused — tracker silently no-ops
            // until the user grants it. Settings reflects the state.
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source

        startFlushTimer()
        installHotkeyMonitor()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        flushTimer?.cancel()
        flushTimer = nil

        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }

        flushNow()
    }

    /// Pause input capture for `pauseDurationSeconds`. Re-arms the timer if
    /// already paused. Called from the global hotkey handler.
    func pause(duration: TimeInterval = InputEventTracker.pauseDurationSeconds) {
        let until = Date().timeIntervalSince1970 + duration
        os_unfair_lock_lock(&bufferLock)
        pausedUntilTimestamp = until
        os_unfair_lock_unlock(&bufferLock)
        UserDefaults.standard.set(until, forKey: Self.pausedUntilKey)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangePauseStateNotification, object: nil)
        }
    }

    func resume() {
        os_unfair_lock_lock(&bufferLock)
        pausedUntilTimestamp = 0
        os_unfair_lock_unlock(&bufferLock)
        UserDefaults.standard.removeObject(forKey: Self.pausedUntilKey)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangePauseStateNotification, object: nil)
        }
    }

    /// Re-read settings from UserDefaults. Called on a Combine observer when
    /// the user toggles things in Settings.
    func reloadSettings() {
        loadSettings()
    }

    /// Wipe every input row + every aggregate. Used by the destructive
    /// "Delete all input data" button in Settings.
    static func deleteAllData() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dbURL = try HistoryStore.inputTrackingDatabaseURL()
                var handle: OpaquePointer?
                guard sqlite3_open_v2(
                    dbURL.path, &handle,
                    SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
                ) == SQLITE_OK, let db = handle else {
                    if let handle { sqlite3_close(handle) }
                    return
                }
                defer { sqlite3_close(db) }
                sqlite3_busy_timeout(db, 5000)
                let sql = """
                BEGIN;
                DELETE FROM keystroke_events;
                DELETE FROM mouse_events;
                DELETE FROM typed_words;
                DELETE FROM cursor_heatmap_bins;
                DELETE FROM input_tracking_meta;
                COMMIT;
                VACUUM;
                """
                sqlite3_exec(db, sql, nil, nil, nil)
            } catch {
                NSLog("[InputEventTracker] deleteAllData failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Tap callback

    /// C entry point. Must avoid SQLite, NSWorkspace, AppKit calls — those
    /// happen on the flush timer.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let tracker = Unmanaged<InputEventTracker>.fromOpaque(refcon).takeUnretainedValue()

        // Re-enable the tap if the system disabled it (timeout or user input).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tracker.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        tracker.handleEvent(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let now = Date().timeIntervalSince1970

        os_unfair_lock_lock(&bufferLock)
        let paused = pausedUntilTimestamp > now
        let keystrokeLevel = self.keystrokeLevel
        let cursorLevel = self.cursorLevel
        os_unfair_lock_unlock(&bufferLock)

        guard !paused else { return }

        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            guard !keystrokeLevel.isOff else { return }
            // We only persist key DOWN events to keep volume sane.
            guard type == .keyDown else { return }

            let rawKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let modifiers = event.flags.rawValue

            let storedKeyCode: Int64 = keystrokeLevel.capturesKeyCode ? rawKeyCode : 0
            let storedModifiers: Int64 = keystrokeLevel.capturesKeyCode
                ? Int64(bitPattern: UInt64(modifiers))
                : 0
            let storedChar: String? = keystrokeLevel.capturesContent
                ? Self.character(from: event)
                : nil

            let pending = PendingKeystroke(
                ts: now,
                keyCode: storedKeyCode,
                modifiers: storedModifiers,
                char: storedChar
            )
            os_unfair_lock_lock(&bufferLock)
            keystrokeBuffer.append(pending)
            os_unfair_lock_unlock(&bufferLock)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged,
             .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp, .otherMouseDown,
             .scrollWheel:
            guard !cursorLevel.isOff else { return }

            // Filter by level: clicks need .heatmapAndClicks+, scrolls need .fullTrail.
            switch type {
            case .leftMouseDown, .leftMouseUp,
                 .rightMouseDown, .rightMouseUp, .otherMouseDown:
                guard cursorLevel.capturesClicks else { return }
            case .scrollWheel:
                guard cursorLevel.capturesScrolls else { return }
            default:
                break
            }

            let location = event.location
            let kind: Int
            switch type {
            case .mouseMoved: kind = 0
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = 1
            case .leftMouseUp, .rightMouseUp: kind = 2
            case .scrollWheel: kind = 3
            case .leftMouseDragged, .rightMouseDragged: kind = 4
            default: kind = 0
            }

            var button: Int = 0
            if type == .leftMouseDown || type == .leftMouseUp { button = 1 }
            if type == .rightMouseDown || type == .rightMouseUp { button = 2 }
            if type == .otherMouseDown { button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) }

            var dx: Double? = nil
            var dy: Double? = nil
            if type == .scrollWheel {
                dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
                dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            }

            let pending = PendingMouseEvent(
                ts: now,
                kind: kind,
                button: button,
                x: location.x,
                y: location.y,
                scrollDX: dx,
                scrollDY: dy
            )
            os_unfair_lock_lock(&bufferLock)
            mouseBuffer.append(pending)
            os_unfair_lock_unlock(&bufferLock)

        default:
            break
        }
    }

    // MARK: - Flush

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.flushNow()
        }
        flushTimer = timer
        timer.resume()
    }

    private func flushNow() {
        os_unfair_lock_lock(&bufferLock)
        let keystrokes = keystrokeBuffer
        let mouseEvents = mouseBuffer
        keystrokeBuffer.removeAll(keepingCapacity: true)
        mouseBuffer.removeAll(keepingCapacity: true)
        let exclusions = exclusionSet
        os_unfair_lock_unlock(&bufferLock)

        guard !keystrokes.isEmpty || !mouseEvents.isEmpty else { return }

        let snapshot = ActiveAppTracker.shared.snapshot()
        guard snapshot.isScreenActive else { return }

        // Drop everything if the active app is excluded.
        if let bundleID = snapshot.bundleID, exclusions.contains(bundleID) {
            return
        }

        let bundleID = snapshot.bundleID
        let secureInput = snapshot.secureInput
        let appName = bundleID
        let deviceID = DeviceInfo.current().id
        let screens = Self.screenSnapshot()

        do {
            let dbURL = try HistoryStore.inputTrackingDatabaseURL()
            var handle: OpaquePointer?
            guard sqlite3_open_v2(
                dbURL.path, &handle,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
            ) == SQLITE_OK, let db = handle else {
                if let handle { sqlite3_close(handle) }
                return
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 5000)
            sqlite3_exec(db, "BEGIN", nil, nil, nil)

            if !keystrokes.isEmpty {
                writeKeystrokes(
                    keystrokes,
                    db: db,
                    bundleID: bundleID,
                    appName: appName,
                    deviceID: deviceID,
                    secureInput: secureInput
                )
            }
            if !mouseEvents.isEmpty {
                writeMouseEvents(
                    mouseEvents,
                    db: db,
                    bundleID: bundleID,
                    appName: appName,
                    deviceID: deviceID,
                    screens: screens
                )
            }

            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        } catch {
            NSLog("[InputEventTracker] flush error: \(error.localizedDescription)")
        }
    }

    private func writeKeystrokes(
        _ events: [PendingKeystroke],
        db: OpaquePointer,
        bundleID: String?,
        appName: String?,
        deviceID: String,
        secureInput: Bool
    ) {
        let sql = """
        INSERT INTO keystroke_events
            (ts, bundle_id, app_name, key_code, modifiers, char, is_word_boundary, secure_input, device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for evt in events {
            sqlite3_reset(statement)
            sqlite3_bind_double(statement, 1, evt.ts)
            if let b = bundleID {
                sqlite3_bind_text(statement, 2, b, -1, transient)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            if let n = appName {
                sqlite3_bind_text(statement, 3, n, -1, transient)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int64(statement, 4, evt.keyCode)
            sqlite3_bind_int64(statement, 5, evt.modifiers)

            if secureInput {
                sqlite3_bind_null(statement, 6)
            } else if let c = evt.char {
                sqlite3_bind_text(statement, 6, c, -1, transient)
            } else {
                sqlite3_bind_null(statement, 6)
            }

            let isBoundary = Self.isWordBoundary(keyCode: evt.keyCode, char: evt.char)
            sqlite3_bind_int(statement, 7, isBoundary ? 1 : 0)
            sqlite3_bind_int(statement, 8, secureInput ? 1 : 0)
            sqlite3_bind_text(statement, 9, deviceID, -1, transient)

            sqlite3_step(statement)
        }
    }

    private func writeMouseEvents(
        _ events: [PendingMouseEvent],
        db: OpaquePointer,
        bundleID: String?,
        appName: String?,
        deviceID: String,
        screens: [(id: Int, frame: CGRect)]
    ) {
        let sql = """
        INSERT INTO mouse_events
            (ts, bundle_id, app_name, kind, button, x, y, screen_id, scroll_dx, scroll_dy, device_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let statement = stmt else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for evt in events {
            sqlite3_reset(statement)
            sqlite3_bind_double(statement, 1, evt.ts)
            if let b = bundleID {
                sqlite3_bind_text(statement, 2, b, -1, transient)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            if let n = appName {
                sqlite3_bind_text(statement, 3, n, -1, transient)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int(statement, 4, Int32(evt.kind))
            sqlite3_bind_int(statement, 5, Int32(evt.button))
            sqlite3_bind_double(statement, 6, evt.x)
            sqlite3_bind_double(statement, 7, evt.y)
            sqlite3_bind_int(statement, 8, Int32(Self.screenID(for: CGPoint(x: evt.x, y: evt.y), screens: screens)))
            if let dx = evt.scrollDX {
                sqlite3_bind_double(statement, 9, dx)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            if let dy = evt.scrollDY {
                sqlite3_bind_double(statement, 10, dy)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            sqlite3_bind_text(statement, 11, deviceID, -1, transient)

            sqlite3_step(statement)
        }
    }

    // MARK: - Hotkey

    private func installHotkeyMonitor() {
        // ⌥⌘P — Option+Command+P. Pause for 30 minutes when pressed.
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let pKey: UInt16 = 35  // kVK_ANSI_P
            guard event.keyCode == pKey,
                  event.modifierFlags.contains(.command),
                  event.modifierFlags.contains(.option) else { return }
            self.pause()
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        let defaults = UserDefaults.standard
        let nextExclusionSet: Set<String>
        if let stored = defaults.array(forKey: Self.exclusionListKey) as? [String], !stored.isEmpty {
            nextExclusionSet = Set(stored)
        } else {
            nextExclusionSet = Self.defaultExclusions
        }
        let pausedUntil = defaults.double(forKey: Self.pausedUntilKey)

        let nextKeystroke = Self.resolveKeystrokeLevel(defaults: defaults)
        let nextCursor = Self.resolveCursorLevel(defaults: defaults)

        os_unfair_lock_lock(&bufferLock)
        self.exclusionSet = nextExclusionSet
        self.pausedUntilTimestamp = pausedUntil
        self.keystrokeLevel = nextKeystroke
        self.cursorLevel = nextCursor
        os_unfair_lock_unlock(&bufferLock)
    }

    /// Resolves the active keystroke level from UserDefaults, with one-shot
    /// migration from the legacy `captureContentKey` boolean.
    static func resolveKeystrokeLevel(defaults: UserDefaults = .standard) -> KeystrokeTrackingLevel {
        if let raw = defaults.string(forKey: keystrokeLevelKey),
           let level = KeystrokeTrackingLevel(rawValue: raw) {
            return level
        }
        // Migration: legacy users who toggled "Record actual letters" jump
        // straight to .fullContent. Otherwise default to .perKey when the
        // master toggle is on, .off when it isn't.
        let masterEnabled = defaults.bool(forKey: enabledKey)
        if defaults.bool(forKey: captureContentKey) {
            return .fullContent
        }
        return masterEnabled ? .perKey : .off
    }

    static func resolveCursorLevel(defaults: UserDefaults = .standard) -> CursorTrackingLevel {
        if let raw = defaults.string(forKey: cursorLevelKey),
           let level = CursorTrackingLevel(rawValue: raw) {
            return level
        }
        let masterEnabled = defaults.bool(forKey: enabledKey)
        return masterEnabled ? .heatmap : .off
    }

    /// True when at least one stream is set to a non-off level. Drives the
    /// sidebar visibility and the boot path.
    static var isAnyStreamEnabled: Bool {
        resolveKeystrokeLevel() != .off || resolveCursorLevel() != .off
    }

    // MARK: - Notifications

    static let didChangePauseStateNotification = Notification.Name("InputEventTrackerDidChangePauseState")

    // MARK: - Helpers

    /// Word boundary detection: space/return/tab and any punctuation reset the
    /// current word in the aggregator.
    private static func isWordBoundary(keyCode: Int64, char: String?) -> Bool {
        if keyCode == 36 || keyCode == 48 || keyCode == 49 || keyCode == 76 {
            return true  // return, tab, space, numpad enter
        }
        guard let c = char, !c.isEmpty else { return false }
        let scalar = c.unicodeScalars.first!
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
        if CharacterSet.punctuationCharacters.contains(scalar) { return true }
        return false
    }

    /// Convert a CGEvent keystroke into the user-visible character (respecting
    /// modifiers — so Shift+a → "A"). Falls back to nil if the OS can't
    /// produce a string for that event.
    private static func character(from event: CGEvent) -> String? {
        var unicodeStringLength: Int = 0
        var buffer: [UniChar] = Array(repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &unicodeStringLength, unicodeString: &buffer)
        guard unicodeStringLength > 0 else { return nil }
        let result = String(utf16CodeUnits: buffer, count: unicodeStringLength)
        // Skip control characters (return, tab, etc. — those are detected via key code).
        if result.unicodeScalars.contains(where: { $0.value < 32 }) {
            return nil
        }
        return result
    }

    /// Snapshot of NSScreen state suitable for passing to the flush thread.
    /// Indexed in the order NSScreen.screens reports them.
    private static func screenSnapshot() -> [(id: Int, frame: CGRect)] {
        let screens = NSScreen.screens
        return screens.enumerated().map { ($0.offset, $0.element.frame) }
    }

    private static func screenID(for point: CGPoint, screens: [(id: Int, frame: CGRect)]) -> Int {
        for screen in screens where screen.frame.contains(point) {
            return screen.id
        }
        return 0
    }
}

// MARK: - Pending event types

private struct PendingKeystroke {
    let ts: Double
    let keyCode: Int64
    let modifiers: Int64
    let char: String?
}

private struct PendingMouseEvent {
    let ts: Double
    let kind: Int
    let button: Int
    let x: Double
    let y: Double
    let scrollDX: Double?
    let scrollDY: Double?
}
