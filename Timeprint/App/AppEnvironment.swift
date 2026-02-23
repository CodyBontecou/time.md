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

private struct AppEnvironmentKey: EnvironmentKey {
    static var defaultValue: AppEnvironment { .preview }
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
