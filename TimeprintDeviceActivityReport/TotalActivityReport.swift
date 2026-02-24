import DeviceActivity
import SwiftUI

/// Context containing total activity data from Screen Time
struct TotalActivityContext {
    let totalDuration: TimeInterval
    let categoryDurations: [(name: String, duration: TimeInterval)]
    let date: Date
}

/// Report scene that computes total activity from DeviceActivityResults
struct TotalActivityReport: DeviceActivityReportScene {
    
    let context: DeviceActivityReport.Context = .init(rawValue: "TotalActivity")
    
    let content: (TotalActivityContext) -> TotalActivityView
    
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TotalActivityContext {
        var totalDuration: TimeInterval = 0
        var categoryDurations: [String: TimeInterval] = [:]
        
        // Iterate through all device activity data
        for await deviceData in data {
            // Iterate through activity segments
            for await segment in deviceData.activitySegments {
                // Get total active duration from segment
                totalDuration += segment.totalActivityDuration
                
                // Aggregate by category
                for await categoryActivity in segment.categories {
                    let categoryName = categoryActivity.category.localizedDisplayName ?? "Other"
                    categoryDurations[categoryName, default: 0] += categoryActivity.totalActivityDuration
                }
            }
        }
        
        // Sort categories by duration
        let sortedCategories = categoryDurations
            .map { (name: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
        
        // Write to shared data store for sync
        await recordToSharedStore(
            totalDuration: totalDuration,
            categoryDurations: sortedCategories
        )
        
        return TotalActivityContext(
            totalDuration: totalDuration,
            categoryDurations: sortedCategories,
            date: Date()
        )
    }
    
    private func recordToSharedStore(totalDuration: TimeInterval, categoryDurations: [(name: String, duration: TimeInterval)]) async {
        // Write to App Group UserDefaults for quick access
        guard let userDefaults = UserDefaults(suiteName: "group.com.codybontecou.Timeprint") else {
            print("[TotalActivityReport] Failed to access App Group UserDefaults")
            return
        }
        
        print("[TotalActivityReport] Recording totalDuration: \(totalDuration), categories: \(categoryDurations.count)")
        
        userDefaults.set(totalDuration, forKey: "todayTotalDuration")
        userDefaults.set(Date(), forKey: "lastReportUpdate")
        
        // Store category breakdown
        let categoryData = categoryDurations.map { ["name": $0.name, "duration": $0.duration] }
        userDefaults.set(categoryData, forKey: "categoryDurations")
        
        // Force synchronize to ensure data is persisted immediately
        userDefaults.synchronize()
        
        print("[TotalActivityReport] Data saved to App Group UserDefaults")
    }
}
