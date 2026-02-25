import DeviceActivity
import SwiftUI

/// Context containing total activity data from Screen Time
struct TotalActivityContext {
    let totalDuration: TimeInterval
    let categoryDurations: [(name: String, duration: TimeInterval)]
    let date: Date
}

/// Report scene that computes total activity from DeviceActivityResults
/// Note: Due to iOS sandbox restrictions, this data can only be displayed visually
/// via DeviceActivityReport - it cannot be exported to the host app programmatically.
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
        
        return TotalActivityContext(
            totalDuration: totalDuration,
            categoryDurations: sortedCategories,
            date: Date()
        )
    }
}
