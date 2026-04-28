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
    @AppStorage("hasCompletedMacOnboarding") private var hasCompletedMacOnboarding: Bool = false
    @AppStorage("isGrandfathered") private var isGrandfathered: Bool = false
    @StateObject private var subscriptionStore = SubscriptionStore.shared

    #if !APPSTORE
    /// Sparkle updater controller for auto-updates
    @StateObject private var updaterController = UpdaterController()
    #endif

    init() {
        Self.performGrandfatherCheckIfNeeded()
    }

    /// Stamps `isGrandfathered` once when the paywall build first launches.
    /// Anyone who already completed onboarding under a free build is considered
    /// an existing user and gets lifetime access without going through the paywall.
    private static func performGrandfatherCheckIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "grandfatherCheckPerformed"
        guard !defaults.bool(forKey: key) else { return }
        let isExistingUser = defaults.bool(forKey: "hasCompletedMacOnboarding")
        defaults.set(isExistingUser, forKey: "isGrandfathered")
        defaults.set(true, forKey: key)
    }

    private var hasFullAccess: Bool {
        isGrandfathered || subscriptionStore.isEntitled
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if hasFullAccess && hasCompletedMacOnboarding {
                    RootSplitView(filters: filters, navigation: navigation)
                } else if !hasCompletedMacOnboarding {
                    MacOnboardingView(
                        isPresented: .init(
                            get: { !hasCompletedMacOnboarding },
                            set: { if !$0 { hasCompletedMacOnboarding = true } }
                        ),
                        requiresPaywall: !isGrandfathered
                    )
                } else {
                    // Lapsed: completed onboarding previously but no active subscription.
                    PaywallView()
                        .frame(minWidth: 640, minHeight: 520)
                        .background(BrutalTheme.background)
                }
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
                Task { await subscriptionStore.refreshEntitlement() }
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
