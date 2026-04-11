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
    @State private var lastCloudSyncDate: Date?
    @State private var cloudSyncError: String?
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedMacOnboarding")
    
    #if !APPSTORE
    /// Sparkle updater controller for auto-updates
    @StateObject private var updaterController = UpdaterController()
    #endif

    /// Fires every 15 minutes while the app is running to capture new Screen Time data.
    private let localSyncTimer = Timer.publish(every: 900, on: .main, in: .common).autoconnect()
    
    /// Fires every 15 minutes to sync data to iCloud for the iOS companion app.
    private let cloudSyncTimer = Timer.publish(every: 900, on: .main, in: .common).autoconnect()

    init() {
        // When launched by the background Launch Agent, perform a sync and
        // exit immediately — no windows, no Dock icon.
        if CommandLine.arguments.contains("--background-sync") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            HistoryStore.forceSync()
            
            // Also perform cloud sync in background mode
            Self.performBackgroundCloudSync()
            
            // Give a moment for async work to complete
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
            Darwin.exit(0)
        }
    }
    
    /// Static method for background cloud sync (can be called from init)
    private static func performBackgroundCloudSync() {
        Task {
            guard let syncCoordinator = AppEnvironment.live.syncCoordinator else {
                print("[CloudSync] SyncCoordinator not available")
                return
            }
            
            do {
                try await syncCoordinator.performSync()
                print("[CloudSync] Background sync completed successfully")
            } catch {
                print("[CloudSync] Background sync failed: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView(filters: filters, navigation: navigation)
                .environment(\.appEnvironment, .live)
                .environment(\.appNameDisplayMode, AppNameDisplayMode(rawValue: appNameDisplayMode) ?? .short)
                .environment(navigation)
                .task { await initialSync() }
                .task { await initialCloudSync() }
                .task { installBackgroundAgent() }
                .sheet(isPresented: $showOnboarding) {
                    MacOnboardingView(isPresented: $showOnboarding)
                }
                .onReceive(localSyncTimer) { _ in
                    Task.detached(priority: .utility) {
                        HistoryStore.syncIfNeeded()
                    }
                }
                .onReceive(cloudSyncTimer) { _ in
                    Task {
                        await performCloudSync()
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1360, height: 860)
        .commands {
            #if APPSTORE
            TimeMdCommands(
                navigation: navigation,
                filters: filters,
                performCloudSync: performCloudSync
            )
            #else
            TimeMdCommands(
                navigation: navigation,
                filters: filters,
                performCloudSync: performCloudSync,
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
        Task.detached(priority: .utility) {
            HistoryStore.syncIfNeeded()
        }
        
        // Prefetch browser history databases in background so Web History view loads instantly
        Task.detached(priority: .utility) {
            SQLiteBrowsingHistoryService().prefetchDatabases()
        }
    }
    
    /// Perform initial cloud sync on app launch.
    private func initialCloudSync() async {
        // Small delay to let local sync complete first
        try? await Task.sleep(for: .seconds(2))
        await performCloudSync()
    }
    
    /// Sync screen time data to iCloud for the iOS companion app.
    /// Runs sync in a detached task to avoid blocking the main thread
    /// (NSFileCoordinator can block while coordinating file access).
    @MainActor
    private func performCloudSync() async {
        guard let syncCoordinator = AppEnvironment.live.syncCoordinator else {
            print("[CloudSync] SyncCoordinator not available")
            return
        }
        
        // Run sync in detached task to prevent main thread blocking
        let error: Error? = await Task.detached(priority: .utility) {
            do {
                try await syncCoordinator.performSync()
                return nil
            } catch {
                return error
            }
        }.value
        
        // Update state on main actor
        if let error {
            cloudSyncError = error.localizedDescription
            print("[CloudSync] Failed to sync: \(error.localizedDescription)")
        } else {
            lastCloudSyncDate = Date()
            cloudSyncError = nil
            print("[CloudSync] Successfully synced to iCloud at \(Date())")
        }
    }

    /// Register (or update) the Launch Agent that syncs every 4 hours
    /// in the background, even when the app isn't running.
    private func installBackgroundAgent() {
        Task.detached(priority: .utility) {
            BackgroundSyncManager.install()
        }
    }
}
