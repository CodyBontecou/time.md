import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os.log

/// Service for scheduling DeviceActivity monitoring intervals.
/// Must be called after FamilyControls authorization is granted.
@MainActor
final class MonitoringScheduler: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isMonitoringActive: Bool = false
    @Published private(set) var lastScheduleError: String?
    @Published private(set) var activeSchedules: [String] = []
    
    // MARK: - Private Properties
    
    private let center = DeviceActivityCenter()
    private let logger = Logger(subsystem: "com.codybontecou.Timeprint", category: "MonitoringScheduler")
    private let userDefaults = UserDefaults.appGroup
    
    // MARK: - Initialization
    
    init() {
        refreshActiveSchedules()
    }
    
    // MARK: - Public Methods
    
    /// Start daily monitoring (midnight to midnight)
    func startDailyMonitoring() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true,
            warningTime: DateComponents(minute: 5)
        )
        
        do {
            try center.startMonitoring(.daily, during: schedule)
            logger.info("Daily monitoring started successfully")
            isMonitoringActive = true
            lastScheduleError = nil
            userDefaults?.set(true, forKey: Keys.dailyMonitoringEnabled)
            userDefaults?.set(Date(), forKey: Keys.lastScheduleDate)
            refreshActiveSchedules()
        } catch {
            logger.error("Failed to start daily monitoring: \(error.localizedDescription)")
            lastScheduleError = error.localizedDescription
            throw error
        }
    }
    
    /// Start hourly monitoring for finer granularity
    func startHourlyMonitoring() throws {
        // Create 24 hourly schedules
        for hour in 0..<24 {
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: hour, minute: 0, second: 0),
                intervalEnd: DateComponents(hour: hour, minute: 59, second: 59),
                repeats: true
            )
            
            let activityName = DeviceActivityName("hourly_\(hour)")
            
            do {
                try center.startMonitoring(activityName, during: schedule)
            } catch {
                logger.error("Failed to start hourly monitoring for hour \(hour): \(error.localizedDescription)")
                // Continue with other hours
            }
        }
        
        logger.info("Hourly monitoring started")
        userDefaults?.set(true, forKey: Keys.hourlyMonitoringEnabled)
        refreshActiveSchedules()
    }
    
    /// Start work hours monitoring (9am-5pm weekdays)
    func startWorkHoursMonitoring() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 9, minute: 0),
            intervalEnd: DateComponents(hour: 17, minute: 0),
            repeats: true,
            warningTime: DateComponents(minute: 15)
        )
        
        do {
            try center.startMonitoring(.workHours, during: schedule)
            logger.info("Work hours monitoring started")
            userDefaults?.set(true, forKey: Keys.workHoursMonitoringEnabled)
            refreshActiveSchedules()
        } catch {
            logger.error("Failed to start work hours monitoring: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Start evening monitoring (6pm-11pm)
    func startEveningMonitoring() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 18, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 0),
            repeats: true
        )
        
        do {
            try center.startMonitoring(.evening, during: schedule)
            logger.info("Evening monitoring started")
            userDefaults?.set(true, forKey: Keys.eveningMonitoringEnabled)
            refreshActiveSchedules()
        } catch {
            logger.error("Failed to start evening monitoring: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Stop all monitoring
    func stopAllMonitoring() {
        center.stopMonitoring()
        isMonitoringActive = false
        
        userDefaults?.set(false, forKey: Keys.dailyMonitoringEnabled)
        userDefaults?.set(false, forKey: Keys.hourlyMonitoringEnabled)
        userDefaults?.set(false, forKey: Keys.workHoursMonitoringEnabled)
        userDefaults?.set(false, forKey: Keys.eveningMonitoringEnabled)
        
        logger.info("All monitoring stopped")
        refreshActiveSchedules()
    }
    
    /// Stop a specific monitoring schedule
    func stopMonitoring(_ activity: DeviceActivityName) {
        center.stopMonitoring([activity])
        logger.info("Stopped monitoring: \(activity.rawValue)")
        refreshActiveSchedules()
    }
    
    /// Re-establish schedules after app launch (call on app launch)
    func restoreSchedulesIfNeeded() {
        guard let defaults = userDefaults else { return }
        
        if defaults.bool(forKey: Keys.dailyMonitoringEnabled) {
            do {
                try startDailyMonitoring()
            } catch {
                logger.error("Failed to restore daily monitoring: \(error.localizedDescription)")
            }
        }
        
        if defaults.bool(forKey: Keys.hourlyMonitoringEnabled) {
            do {
                try startHourlyMonitoring()
            } catch {
                logger.error("Failed to restore hourly monitoring: \(error.localizedDescription)")
            }
        }
        
        if defaults.bool(forKey: Keys.workHoursMonitoringEnabled) {
            do {
                try startWorkHoursMonitoring()
            } catch {
                logger.error("Failed to restore work hours monitoring: \(error.localizedDescription)")
            }
        }
        
        if defaults.bool(forKey: Keys.eveningMonitoringEnabled) {
            do {
                try startEveningMonitoring()
            } catch {
                logger.error("Failed to restore evening monitoring: \(error.localizedDescription)")
            }
        }
    }
    
    /// Set up usage threshold events
    func setDailyUsageThreshold(minutes: Int, selection: FamilyActivitySelection) throws {
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: minutes)
        )
        
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            .dailyTotal(minutes: minutes): event
        ]
        
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        try center.startMonitoring(.daily, during: schedule, events: events)
        logger.info("Set daily usage threshold: \(minutes) minutes")
    }
    
    // MARK: - Private Methods
    
    private func refreshActiveSchedules() {
        activeSchedules = center.activities.map { $0.rawValue }
        isMonitoringActive = !activeSchedules.isEmpty
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let dailyMonitoringEnabled = "dailyMonitoringEnabled"
        static let hourlyMonitoringEnabled = "hourlyMonitoringEnabled"
        static let workHoursMonitoringEnabled = "workHoursMonitoringEnabled"
        static let eveningMonitoringEnabled = "eveningMonitoringEnabled"
        static let lastScheduleDate = "lastScheduleDate"
    }
}

// MARK: - DeviceActivityName Extensions

extension DeviceActivityName {
    /// Daily monitoring activity (midnight to midnight)
    static let daily = DeviceActivityName("daily")
    
    /// Work hours monitoring (9am-5pm)
    static let workHours = DeviceActivityName("workHours")
    
    /// Evening monitoring (6pm-11pm)
    static let evening = DeviceActivityName("evening")
}

// MARK: - DeviceActivityEvent.Name Extensions

extension DeviceActivityEvent.Name {
    /// Total daily screen time threshold
    static func dailyTotal(minutes: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("dailyTotal_\(minutes)m")
    }
}
