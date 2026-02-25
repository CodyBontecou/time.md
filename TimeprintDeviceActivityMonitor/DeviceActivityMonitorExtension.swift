import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import os.log

/// Device Activity Monitor Extension that captures usage data in the background.
/// This extension runs even when the main app is not active.
///
/// Note: Due to iOS sandbox restrictions, this extension cannot write data to any
/// shared storage that the host app can read. It can only respond to threshold
/// events and interval lifecycle callbacks.
class TimeprintMonitor: DeviceActivityMonitor {
    
    private let logger = Logger(subsystem: "com.codybontecou.Timeprint.Monitor", category: "DeviceActivity")
    
    // MARK: - Interval Lifecycle
    
    /// Called when a scheduled monitoring interval begins
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.info("Monitoring interval started: \(activity.rawValue)")
    }
    
    /// Called when a scheduled monitoring interval ends
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.info("Monitoring interval ended: \(activity.rawValue)")
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
        
        // Future: Could trigger local notification or update app badge
    }
    
    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        logger.debug("Approaching threshold for event: \(event.rawValue)")
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
