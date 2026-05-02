import AppKit
import Combine
import SwiftUI

@main
struct TimeMdApp: App {
    @NSApplicationDelegateAdaptor(TimeMdAppDelegate.self) private var appDelegate
    @State private var filters = GlobalFilterStore()
    @State private var navigation = NavigationCoordinator()
    @AppStorage("appNameDisplayMode") private var appNameDisplayMode: String = AppNameDisplayMode.short.rawValue
    @AppStorage(AppVisibilityMode.storageKey) private var visibilityModeRaw: String = AppVisibilityMode.dockAndMenuBar.rawValue
    @AppStorage("hasCompletedMacOnboarding") private var hasCompletedMacOnboarding: Bool = false
    @StateObject private var subscriptionStore = SubscriptionStore.shared

    private var visibilityMode: AppVisibilityMode {
        AppVisibilityMode(rawValue: visibilityModeRaw) ?? .dockAndMenuBar
    }

    private var menuBarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { visibilityMode.showsMenuBar },
            set: { _ in /* read-only mirror of `visibilityMode` */ }
        )
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if subscriptionStore.isEntitled && hasCompletedMacOnboarding {
                    RootSplitView(filters: filters, navigation: navigation)
                } else if !hasCompletedMacOnboarding {
                    MacOnboardingView(
                        isPresented: .init(
                            get: { !hasCompletedMacOnboarding },
                            set: { if !$0 { hasCompletedMacOnboarding = true } }
                        )
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
            .onChange(of: visibilityModeRaw) { _, _ in
                visibilityMode.apply()
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
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1360, height: 860)
        .commands {
            TimeMdCommands(
                navigation: navigation,
                filters: filters
            )
        }

        // Menu bar extra for quick access to today's screen time
        MenuBarExtra(isInserted: menuBarVisibilityBinding) {
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

/// Applies the saved `AppVisibilityMode` at launch and routes reopen
/// events (Spotlight / Finder / Dock-clicks) back to the main window so
/// the app remains reachable in `.menuBarOnly` and `.hidden` modes.
final class TimeMdAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppVisibilityMode.current.applyImmediately()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
