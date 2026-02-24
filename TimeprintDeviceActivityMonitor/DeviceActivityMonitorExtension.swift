import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import os.log

/// Device Activity Monitor Extension that captures usage data in the background.
/// This extension runs even when the main app is not active.
class TimeprintMonitor: DeviceActivityMonitor {
    
    private let logger = Logger(subsystem: "com.codybontecou.Timeprint.Monitor", category: "DeviceActivity")
    private let appGroupId = "group.com.codybontecou.Timeprint"
    
    // MARK: - Interval Lifecycle
    
    /// Called when a scheduled monitoring interval begins
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.info("Monitoring interval started: \(activity.rawValue)")
        
        // Mark monitoring as active
        setMonitoringActive(true)
    }
    
    /// Called when a scheduled monitoring interval ends
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.info("Monitoring interval ended: \(activity.rawValue)")
        
        // Record the completed interval
        recordIntervalCompletion(for: activity)
        
        // Mark monitoring as inactive
        setMonitoringActive(false)
    }
    
    /// Called periodically during an active interval
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        logger.debug("Interval will start soon: \(activity.rawValue)")
    }
    
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        logger.debug("Interval will end soon: \(activity.rawValue)")
    }
    
    // MARK: - Event Thresholds
    
    /// Called when a usage threshold is reached for a specific event
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.info("Threshold reached for event: \(event.rawValue) in activity: \(activity.rawValue)")
        
        // Store the event for later sync
        recordThresholdEvent(event: event, activity: activity)
    }
    
    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        logger.debug("Approaching threshold for event: \(event.rawValue)")
    }
    
    // MARK: - Data Recording
    
    private func recordIntervalCompletion(for activity: DeviceActivityName) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            logger.error("Failed to access App Group UserDefaults")
            return
        }
        
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateKey = formatter.string(from: now)
        
        // Increment completed intervals count for today
        var intervals = userDefaults.dictionary(forKey: "completedIntervals") as? [String: Int] ?? [:]
        intervals[dateKey, default: 0] += 1
        userDefaults.set(intervals, forKey: "completedIntervals")
        
        // Store last interval end time
        userDefaults.set(now, forKey: "lastIntervalEndTime")
        
        // Trigger sync notification
        notifyMainApp(event: "intervalEnded")
        
        logger.info("Recorded interval completion for \(dateKey)")
    }
    
    private func recordThresholdEvent(event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            logger.error("Failed to access App Group UserDefaults")
            return
        }
        
        // Store threshold events
        var events = userDefaults.array(forKey: "thresholdEvents") as? [[String: Any]] ?? []
        
        let eventData: [String: Any] = [
            "event": event.rawValue,
            "activity": activity.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        events.append(eventData)
        
        // Keep only last 100 events
        if events.count > 100 {
            events = Array(events.suffix(100))
        }
        
        userDefaults.set(events, forKey: "thresholdEvents")
        
        logger.info("Recorded threshold event: \(event.rawValue)")
    }
    
    private func setMonitoringActive(_ active: Bool) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else { return }
        userDefaults.set(active, forKey: "isMonitoringActive")
        userDefaults.set(Date(), forKey: active ? "monitoringStartTime" : "monitoringEndTime")
    }
    
    private func notifyMainApp(event: String) {
        // Post a Darwin notification that the main app can observe
        let notificationName = CFNotificationName("com.codybontecou.Timeprint.monitorEvent" as CFString)
        
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }
}

// MARK: - Device Activity Names

extension DeviceActivityName {
    /// Daily monitoring activity (midnight to midnight)
    static let daily = DeviceActivityName("daily")
    
    /// Hourly monitoring activity
    static let hourly = DeviceActivityName("hourly")
    
    /// Work hours monitoring (9am-5pm weekdays)
    static let workHours = DeviceActivityName("workHours")
    
    /// Evening monitoring (6pm-11pm)
    static let evening = DeviceActivityName("evening")
}

// MARK: - Device Activity Events

extension DeviceActivityEvent.Name {
    /// Total daily screen time threshold
    static func dailyTotal(minutes: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("dailyTotal_\(minutes)m")
    }
    
    /// Individual app usage threshold
    static func appUsage(bundleId: String, minutes: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("app_\(bundleId)_\(minutes)m")
    }
    
    /// Category usage threshold
    static func categoryUsage(category: String, minutes: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("category_\(category)_\(minutes)m")
    }
}
