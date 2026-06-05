import AppKit
import Combine
import Sparkle
import SwiftUI

@main
struct TimeMdApp: App {
    @NSApplicationDelegateAdaptor(TimeMdAppDelegate.self) private var appDelegate
    @State private var filters = GlobalFilterStore()
    @State private var navigation = NavigationCoordinator()
    @State private var activationStore = LicenseActivationStore.shared
    @State private var appServicesStarted = false
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @AppStorage("appNameDisplayMode") private var appNameDisplayMode: String = AppNameDisplayMode.short.rawValue
    @AppStorage(AppVisibilityMode.storageKey) private var visibilityModeRaw: String = AppVisibilityMode.dockAndMenuBar.rawValue
    @AppStorage("hasCompletedMacOnboarding") private var hasCompletedMacOnboarding: Bool = false

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
                if !hasCompletedMacOnboarding {
                    MacOnboardingView(
                        isPresented: .init(
                            get: { !hasCompletedMacOnboarding },
                            set: { if !$0 { hasCompletedMacOnboarding = true } }
                        )
                    )
                } else if activationStore.isUnlockedForLaunch {
                    RootSplitView(filters: filters, navigation: navigation)
                } else {
                    LicenseActivationGateView()
                }
            }
            .environment(\.appEnvironment, .live)
            .environment(\.appNameDisplayMode, AppNameDisplayMode(rawValue: appNameDisplayMode) ?? .short)
            .environment(navigation)
            .environment(activationStore)
            .task {
                let trace = PerformanceTrace.begin("TimeMdApp.prepareForLaunch")
                await activationStore.prepareForLaunch()
                PerformanceTrace.end("TimeMdApp.prepareForLaunch", startedAt: trace)
            }
            .task(id: activationStore.isUnlockedForLaunch) {
                PerformanceTrace.event("TimeMdApp unlock state task: unlocked=\(activationStore.isUnlockedForLaunch)")
                if activationStore.isUnlockedForLaunch {
                    await startAppServicesIfNeeded()
                } else {
                    stopAppServicesIfNeeded()
                }
            }
            .onOpenURL { url in
                NSApplication.shared.activate(ignoringOtherApps: true)
                activationStore.handleDeepLink(url)
            }
            .onChange(of: visibilityModeRaw) { _, _ in
                visibilityMode.apply()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                stopAppServicesIfNeeded()
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
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1360, height: 860)
        .commands {
            TimeMdCommands(
                navigation: navigation,
                filters: filters,
                updater: updaterController.updater
            )
        }

        // Menu bar extra for quick access to today's screen time
        MenuBarExtra(isInserted: menuBarVisibilityBinding) {
            Group {
                if activationStore.isUnlockedForLaunch {
                    TimeMdMenuBarExtra()
                } else {
                    LicenseMenuBarExtraView()
                }
            }
            .environment(\.appEnvironment, .live)
            .environment(activationStore)
        } label: {
            Group {
                if activationStore.isUnlockedForLaunch {
                    MenuBarLabel()
                } else {
                    LicenseMenuBarLabel()
                }
            }
            .environment(\.appEnvironment, .live)
            .environment(activationStore)
        }
        .menuBarExtraStyle(.window)
    }

    /// Starts local-only data collectors after trial/license activation has
    /// unlocked the app. Onboarding and the paywall can render before this,
    /// but screen time/browser/input collection stays disabled until entitlement
    /// validation succeeds.
    private func startAppServicesIfNeeded() async {
        guard !appServicesStarted else { return }
        let trace = PerformanceTrace.begin("TimeMdApp.startAppServicesIfNeeded")
        defer { PerformanceTrace.end("TimeMdApp.startAppServicesIfNeeded", startedAt: trace) }
        appServicesStarted = true

        await initialSync()
        ActiveAppTracker.shared.start()
        ScreenTimeAutoSaveWriter.shared.start(dataService: AppEnvironment.live.dataService)
        ScheduledExportEnvironment.runner.start()
        synchronizeBlockingRulesOnLaunch()
        WebsiteAccessEventSource.shared.start()
        AppBlockActivationWatcher.shared.start()
        reconcileDomainBlocksOnLaunch()
        Task.detached(priority: .utility) {
            AppCategorizer.autoPopulateCategories()
        }
        if UserDefaults.standard.bool(forKey: InputEventTracker.enabledKey) {
            InputEventTracker.shared.start()
            InputAggregator.shared.start()
            InputDataPruner.shared.start()
        }
    }

    private func stopAppServicesIfNeeded() {
        guard appServicesStarted else { return }
        ActiveAppTracker.shared.stop()
        ScreenTimeAutoSaveWriter.shared.stop()
        InputEventTracker.shared.stop()
        InputAggregator.shared.stop()
        InputDataPruner.shared.stop()
        WebsiteAccessEventSource.shared.stop()
        AppBlockActivationWatcher.shared.stop()
        appServicesStarted = false
    }

    /// Run immediately after activation so data is captured even if the user
    /// opens the app briefly and closes it without navigating anywhere.
    /// Fire-and-forget — don't block the UI waiting for sync to complete.
    private func initialSync() async {
        // Prefetch browser history databases in background so Web History view loads instantly
        SQLiteBrowsingHistoryService().prefetchDatabases()

        // Start periodic local snapshots for opt-in web history persistence.
        WebHistoryArchiveScheduler.shared.updateForCurrentSettings()

        // One-time: split input-tracking tables out of screentime.db into a
        // sibling DB so the dashboard temp-copy doesn't carry their bulk.
        // Idempotent — gated by a UserDefaults flag inside HistoryStore.
        Task.detached(priority: .utility) {
            _ = try? HistoryStore.inputTrackingDatabaseURL()
        }
    }

    /// Ensure the simplified on/off blocking model is reflected in persisted
    /// active state before browser/app watchers begin enforcing.
    private func synchronizeBlockingRulesOnLaunch() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        do {
            _ = try ManualBlockStateSynchronizer.synchronize(store: LiveBlockingRuleStore(), now: Date())
        } catch {
            NSLog("[TimeMdApp] Failed to synchronize blocking rules on launch: \(error.localizedDescription)")
        }
    }

    /// Re-publish active domain blocks on launch so helper state is repaired
    /// without requiring the user to open the Blocking screen first.
    private func reconcileDomainBlocksOnLaunch() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        Task(priority: .utility) {
            do {
                _ = try await DomainBlockEnforcer(helper: PrivilegedDomainBlockHelperClient.shared)
                    .reconcileActiveDomainBlocks(now: Date())
            } catch {
                NSLog("[TimeMdApp] Failed to reconcile domain blocks on launch: \(error.localizedDescription)")
            }
        }
    }
}

/// Applies the saved `AppVisibilityMode` at launch and routes reopen
/// events (Spotlight / Finder / Dock-clicks) back to the main window so
/// the app remains reachable in `.menuBarOnly` and `.hidden` modes.
final class TimeMdAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PerformanceTrace.event("TimeMdAppDelegate.applicationDidFinishLaunching")
        AppVisibilityMode.current.applyImmediately()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        application.activate(ignoringOtherApps: true)
        Task { @MainActor in
            urls.forEach { LicenseActivationStore.shared.handleDeepLink($0) }
        }
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
