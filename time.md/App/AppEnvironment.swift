import SwiftUI

struct AppEnvironment: Sendable {
    let dataService: any ScreenTimeDataServing
    let exportCoordinator: any ExportCoordinating
    let featureFlags: FeatureFlags

    static let live: AppEnvironment = {
        let dataService = SQLiteScreenTimeDataService()
        return AppEnvironment(
            dataService: dataService,
            exportCoordinator: ExportCoordinator(dataService: dataService),
            featureFlags: .default
        )
    }()

    static let preview: AppEnvironment = {
        let dataService = SQLiteScreenTimeDataService()
        return AppEnvironment(
            dataService: dataService,
            exportCoordinator: ExportCoordinator(dataService: dataService),
            featureFlags: .default
        )
    }()
}

/// Process-wide singletons for the scheduled-export feature. Lives outside
/// `AppEnvironment` because it owns mutable state and a Timer.
@MainActor
enum ScheduledExportEnvironment {
    static let store = ExportScheduleStore()
    static let runner = ScheduledExportRunner(
        store: store,
        dataService: AppEnvironment.live.dataService
    )
}

private struct AppEnvironmentKey: EnvironmentKey {
    static var defaultValue: AppEnvironment { .preview }
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
