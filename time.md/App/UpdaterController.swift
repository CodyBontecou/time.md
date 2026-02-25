#if os(macOS)
import Combine
import Foundation
import Sparkle

/// A helper class to manage Sparkle auto-updates.
/// This class observes the updater state to enable/disable the "Check for Updates" menu item.
@MainActor
final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates = false
    
    init() {
        // Create the updater controller with default UI
        // The updater will automatically check for updates based on user preferences
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Observe when the updater can check for updates
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    /// Triggers a manual check for updates.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    /// Access to the underlying updater for advanced configuration.
    var updater: SPUUpdater {
        updaterController.updater
    }
}
#endif
