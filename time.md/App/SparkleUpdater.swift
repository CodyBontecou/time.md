#if os(macOS)
import Combine
import Sparkle
import SwiftUI

/// View that exposes a "Check for Updates…" menu item bound to a Sparkle
/// updater. Disabled when the updater is busy so the user can't trigger a
/// concurrent check.
struct CheckForUpdatesView: View {
    @ObservedObject private var checker: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checker = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!checker.canCheckForUpdates)
    }
}

/// Bridges Sparkle's KVO-published `canCheckForUpdates` into SwiftUI.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
#endif
