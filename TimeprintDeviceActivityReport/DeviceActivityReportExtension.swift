import DeviceActivity
import SwiftUI

/// Main entry point for the Device Activity Report Extension.
/// This extension provides SwiftUI views that display Screen Time data.
@main
struct TimeprintReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Total activity report for dashboard
        TotalActivityReport { totalActivity in
            TotalActivityView(totalActivity: totalActivity)
        }
        
        // Top apps report
        TopAppsReport { apps in
            TopAppsView(apps: apps)
        }
    }
}
