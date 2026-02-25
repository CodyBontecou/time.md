import DeviceActivity
import SwiftUI

/// Context containing top apps data from Screen Time
struct TopAppsContext {
    let apps: [AppActivityData]
    let date: Date
}

/// Individual app activity data
struct AppActivityData: Identifiable {
    let id = UUID()
    let name: String
    let bundleId: String?
    let duration: TimeInterval
    let pickupCount: Int
    let notificationCount: Int
    let category: String?
}

/// Report scene that computes top apps from DeviceActivityResults
struct TopAppsReport: DeviceActivityReportScene {
    
    let context: DeviceActivityReport.Context = .init(rawValue: "TopApps")
    
    let content: ([AppActivityData]) -> TopAppsView
    
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [AppActivityData] {
        var appData: [String: (name: String, bundleId: String?, duration: TimeInterval, pickups: Int, notifications: Int, category: String?)] = [:]
        
        // Iterate through all device activity data
        for await deviceData in data {
            // Iterate through activity segments
            for await segment in deviceData.activitySegments {
                // Iterate through categories
                for await categoryActivity in segment.categories {
                    let categoryName = categoryActivity.category.localizedDisplayName ?? "Other"
                    
                    // Iterate through apps in this category
                    for await appActivity in categoryActivity.applications {
                        let appName = appActivity.application.localizedDisplayName ?? "Unknown App"
                        let bundleId = appActivity.application.bundleIdentifier
                        let key = bundleId ?? appName
                        
                        if var existing = appData[key] {
                            existing.duration += appActivity.totalActivityDuration
                            existing.pickups += appActivity.numberOfPickups
                            existing.notifications += appActivity.numberOfNotifications
                            appData[key] = existing
                        } else {
                            appData[key] = (
                                name: appName,
                                bundleId: bundleId,
                                duration: appActivity.totalActivityDuration,
                                pickups: appActivity.numberOfPickups,
                                notifications: appActivity.numberOfNotifications,
                                category: categoryName
                            )
                        }
                    }
                }
            }
        }
        
        // Convert to array and sort by duration
        let apps = appData.values.map { app in
            AppActivityData(
                name: app.name,
                bundleId: app.bundleId,
                duration: app.duration,
                pickupCount: app.pickups,
                notificationCount: app.notifications,
                category: app.category
            )
        }
        .sorted { $0.duration > $1.duration }
        
        // Write to shared data store
        await recordAppsToSharedStore(apps: apps)
        
        return apps
    }
    
    private func recordAppsToSharedStore(apps: [AppActivityData]) async {
        guard let userDefaults = UserDefaults(suiteName: "group.com.codybontecou.Timeprint") else {
            print("[TopAppsReport] Failed to access App Group UserDefaults")
            return
        }
        
        print("[TopAppsReport] Recording \(apps.count) apps")
        
        // Store top 20 apps
        let topApps = apps.prefix(20).map { app -> [String: Any] in
            var dict: [String: Any] = [
                "name": app.name,
                "duration": app.duration,
                "pickups": app.pickupCount,
                "notifications": app.notificationCount
            ]
            if let bundleId = app.bundleId {
                dict["bundleId"] = bundleId
            }
            if let category = app.category {
                dict["category"] = category
            }
            return dict
        }
        
        userDefaults.set(topApps, forKey: "topApps")
        userDefaults.set(Date(), forKey: "topAppsLastUpdate")
        
        // Force synchronize to ensure data is persisted immediately
        userDefaults.synchronize()
        
        print("[TopAppsReport] Saved \(topApps.count) apps to App Group UserDefaults")
    }
}
