import AppKit
import Combine
#if !APPSTORE
import Sparkle
#endif
import StoreKit
import SwiftUI

@main
struct TimeMdApp: App {
    @State private var filters = GlobalFilterStore()
    @State private var navigation = NavigationCoordinator()
    @AppStorage("appNameDisplayMode") private var appNameDisplayMode: String = AppNameDisplayMode.short.rawValue
    @AppStorage("showMenuBarItem") private var showMenuBarItem: Bool = true
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedMacOnboarding")
    @StateObject private var storeManager = StoreManager.shared

    #if !APPSTORE
    /// Sparkle updater controller for auto-updates
    @StateObject private var updaterController = UpdaterController()
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                RootSplitView(filters: filters, navigation: navigation)
            }
            .environment(\.appEnvironment, .live)
            .environment(\.appNameDisplayMode, AppNameDisplayMode(rawValue: appNameDisplayMode) ?? .short)
            .environment(navigation)
            .task {
                await initialSync()
                ActiveAppTracker.shared.start()
                Task.detached(priority: .utility) {
                    AppCategorizer.autoPopulateCategories()
                }
            }
            .sheet(isPresented: $showOnboarding) {
                MacOnboardingView(isPresented: $showOnboarding)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                ActiveAppTracker.shared.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: ActiveAppTracker.didRecordSessionNotification)) { _ in
                filters.triggerRefresh()
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1360, height: 860)
        .commands {
            #if APPSTORE
            TimeMdCommands(
                navigation: navigation,
                filters: filters
            )
            #else
            TimeMdCommands(
                navigation: navigation,
                filters: filters,
                updaterController: updaterController
            )
            #endif
        }

        // Menu bar extra for quick access to today's screen time
        MenuBarExtra(isInserted: $showMenuBarItem) {
            TimeMdMenuBarExtra()
                .environment(\.appEnvironment, .live)
        } label: {
            MenuBarLabel()
                .environment(\.appEnvironment, .live)
        }
        .menuBarExtraStyle(.window)
    }

    /// Run immediately on launch so data is captured even if the user
    /// opens the app briefly and closes it without navigating anywhere.
    /// Fire-and-forget — don't block the UI waiting for sync to complete.
    private func initialSync() async {
        // Prefetch browser history databases in background so Web History view loads instantly
        Task.detached(priority: .utility) {
            SQLiteBrowsingHistoryService().prefetchDatabases()
        }
    }
}
