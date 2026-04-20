import AppKit
import Combine
#if !APPSTORE
import Sparkle
#endif
import SwiftUI

@main
struct TimeMdApp: App {
    @State private var filters = GlobalFilterStore()
    @State private var navigation = NavigationCoordinator()
    @AppStorage("appNameDisplayMode") private var appNameDisplayMode: String = AppNameDisplayMode.short.rawValue
    @AppStorage("showMenuBarItem") private var showMenuBarItem: Bool = true
    @AppStorage("hideFromDockWhenClosed") private var hideFromDockWhenClosed: Bool = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedMacOnboarding")

    #if !APPSTORE
    /// Sparkle updater controller for auto-updates
    @StateObject private var updaterController = UpdaterController()
    #endif

    var body: some Scene {
        WindowGroup(id: "main") {
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
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                filters.syncToCurrentPeriodIfFollowing()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                filters.syncToCurrentPeriodIfFollowing()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                handleWindowWillClose(notification)
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

    /// When the last main window closes and the setting is on, drop the Dock
    /// icon so the app lives entirely in the menu bar (hidden from Cmd+Tab).
    /// The menu bar extra's "Open time.md" action restores `.regular` policy.
    private func handleWindowWillClose(_ notification: Notification) {
        guard hideFromDockWhenClosed, showMenuBarItem else { return }
        guard let closingWindow = notification.object as? NSWindow, closingWindow.canBecomeMain else { return }
        DispatchQueue.main.async {
            let hasOtherMainWindow = NSApp.windows.contains { window in
                window !== closingWindow && window.canBecomeMain && window.isVisible
            }
            if !hasOtherMainWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
