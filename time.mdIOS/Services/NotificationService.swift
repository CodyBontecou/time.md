import Foundation
import UserNotifications

/// Manages local notifications for daily screen time summaries
final class NotificationService: NSObject, @unchecked Sendable {
    static let shared = NotificationService()
    
    private let center = UNUserNotificationCenter.current()
    private let dailySummaryIdentifier = "daily-summary"
    
    private override init() {
        super.init()
    }
    
    // MARK: - Authorization
    
    /// Request notification permission
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("[Notifications] Authorization failed: \(error)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Daily Summary Notification
    
    /// Schedule a daily summary notification at the specified hour
    func scheduleDailySummary(at hour: Int = 21, minute: Int = 0) async {
        // Remove existing daily summary
        center.removePendingNotificationRequests(withIdentifiers: [dailySummaryIdentifier])
        
        // Check authorization
        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            print("[Notifications] Not authorized for notifications")
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Daily Screen Time"
        content.body = "Tap to see your screen time summary for today."
        content.sound = .default
        content.categoryIdentifier = "DAILY_SUMMARY"
        
        // Schedule for specified time daily
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailySummaryIdentifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            print("[Notifications] Scheduled daily summary at \(hour):\(String(format: "%02d", minute))")
        } catch {
            print("[Notifications] Failed to schedule: \(error)")
        }
    }
    
    /// Cancel daily summary notifications
    func cancelDailySummary() {
        center.removePendingNotificationRequests(withIdentifiers: [dailySummaryIdentifier])
        print("[Notifications] Cancelled daily summary")
    }
    
    // MARK: - Immediate Notification (for testing)
    
    /// Send an immediate notification with screen time data
    func sendImmediateSummary(todayTotal: Double, weekTotal: Double) async {
        let status = await checkAuthorizationStatus()
        guard status == .authorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Screen Time Summary"
        content.body = "Today: \(formatDuration(todayTotal)) • This week: \(formatDuration(weekTotal))"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
        } catch {
            print("[Notifications] Failed to send immediate: \(error)")
        }
    }
    
    // MARK: - Milestone Notifications
    
    /// Send a notification when user reaches a screen time milestone
    func sendMilestoneNotification(hours: Int) async {
        let status = await checkAuthorizationStatus()
        guard status == .authorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Screen Time Milestone"
        content.body = "You've reached \(hours) hours of screen time today."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "milestone-\(hours)h",
            content: content,
            trigger: trigger
        )
        
        try? await center.add(request)
    }
    
    // MARK: - Badge
    
    /// Update app badge with hours of screen time
    func updateBadge(hours: Int) async {
        let status = await checkAuthorizationStatus()
        guard status == .authorized else { return }
        
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(hours)
        }
    }
    
    /// Clear the app badge
    func clearBadge() async {
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Notification Settings Model

struct NotificationSettings: Codable {
    var dailySummaryEnabled: Bool = false
    var dailySummaryHour: Int = 21
    var dailySummaryMinute: Int = 0
    var milestoneAlertsEnabled: Bool = false
    var badgeEnabled: Bool = false
    
    static let key = "notificationSettings"
    
    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return NotificationSettings()
        }
        return settings
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
