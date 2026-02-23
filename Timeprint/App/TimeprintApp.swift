import AppKit
import Combine
import SwiftUI

@main
struct TimeprintApp: App {
    @State private var filters = GlobalFilterStore()
    @AppStorage("appNameDisplayMode") private var appNameDisplayMode: String = AppNameDisplayMode.short.rawValue

    /// Fires every 15 minutes while the app is running to capture new Screen Time data.
    private let syncTimer = Timer.publish(every: 900, on: .main, in: .common).autoconnect()

    init() {
        // When launched by the background Launch Agent, perform a sync and
        // exit immediately — no windows, no Dock icon.
        if CommandLine.arguments.contains("--background-sync") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            HistoryStore.forceSync()
            Darwin.exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView(filters: filters)
                .environment(\.appEnvironment, .live)
                .environment(\.appNameDisplayMode, AppNameDisplayMode(rawValue: appNameDisplayMode) ?? .short)
                .task { await initialSync() }
                .task { installBackgroundAgent() }
                .onReceive(syncTimer) { _ in
                    Task.detached(priority: .utility) {
                        HistoryStore.syncIfNeeded()
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1360, height: 860)
    }

    /// Run immediately on launch so data is captured even if the user
    /// opens the app briefly and closes it without navigating anywhere.
    private func initialSync() async {
        await Task.detached(priority: .utility) {
            HistoryStore.syncIfNeeded()
        }.value
    }

    /// Register (or update) the Launch Agent that syncs every 4 hours
    /// in the background, even when the app isn't running.
    private func installBackgroundAgent() {
        Task.detached(priority: .utility) {
            BackgroundSyncManager.install()
        }
    }
}
