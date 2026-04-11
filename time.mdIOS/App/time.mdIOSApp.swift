import StoreKit
import SwiftUI

@main
struct TimeMdIOSApp: App {
    @StateObject private var appState = IOSAppState()
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var usageTracker = UsageTracker.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(storeManager)
                .environmentObject(usageTracker)
        }
    }
}

/// Root content view with adaptive navigation (tabs on iPhone, sidebar on iPad)
struct ContentView: View {
    @EnvironmentObject private var appState: IOSAppState
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var usageTracker: UsageTracker
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var selectedDestination: NavigationDestination? = .overview
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var body: some View {
        Group {
            if usageTracker.isTrialExpired && !storeManager.isPurchased {
                IOSPaywallView(store: storeManager, usage: usageTracker)
            } else if horizontalSizeClass == .regular {
                // iPad: Use sidebar navigation
                iPadLayout
            } else {
                // iPhone: Use tab bar
                iPhoneLayout
            }
        }
        .tint(Color.accentColor)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onChange(of: showOnboarding) { oldValue, newValue in
            // When onboarding is dismissed (goes from true to false), refresh app state
            if oldValue == true && newValue == false {
                Task {
                    await appState.onboardingCompleted()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                usageTracker.startSession()
            case .inactive, .background:
                usageTracker.pauseSession()
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - iPhone Layout (Tab Bar)
    
    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            OverviewTab()
                .tabItem {
                    Label("Overview", systemImage: "chart.bar.fill")
                }
                .tag(0)
            
            AppsTab()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2.fill")
                }
                .tag(1)
            
            WebHistoryTab()
                .tabItem {
                    Label("Web", systemImage: "globe")
                }
                .tag(2)
            
            DevicesTab()
                .tabItem {
                    Label("Devices", systemImage: "macbook.and.iphone")
                }
                .tag(3)
            
            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
    }
    
    // MARK: - iPad Layout (Sidebar)
    
    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedDestination) {
                Section("Dashboard") {
                    Label("Overview", systemImage: "chart.bar.fill")
                        .tag(NavigationDestination.overview)
                    
                    Label("Apps", systemImage: "square.grid.2x2.fill")
                        .tag(NavigationDestination.apps)
                    
                    Label("Web History", systemImage: "globe")
                        .tag(NavigationDestination.webHistory)
                    
                    Label("Devices", systemImage: "macbook.and.iphone")
                        .tag(NavigationDestination.devices)
                }
                
                Section {
                    Label("Settings", systemImage: "gear")
                        .tag(NavigationDestination.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("time.md")
        } detail: {
            switch selectedDestination {
            case .overview:
                CompactOverviewView()
                    .navigationBarHidden(true)
            case .apps:
                AppsListView()
                    .navigationTitle("Apps")
            case .webHistory:
                WebHistoryView()
                    .navigationTitle("Web History")
            case .devices:
                AllDevicesView()
                    .navigationTitle("All Devices")
            case .settings:
                IOSSettingsView()
                    .navigationTitle("Settings")
            case .none:
                CompactOverviewView()
                    .navigationBarHidden(true)
            }
        }
    }
}

// MARK: - Navigation Destination

enum NavigationDestination: String, Hashable {
    case overview
    case apps
    case webHistory
    case devices
    case settings
}

// MARK: - Tab Placeholders

struct OverviewTab: View {
    var body: some View {
        NavigationStack {
            CompactOverviewView()
                .navigationBarHidden(true)
        }
    }
}

struct AppsTab: View {
    var body: some View {
        NavigationStack {
            AppsListView()
                .navigationTitle("Apps")
        }
    }
}

struct DevicesTab: View {
    var body: some View {
        NavigationStack {
            AllDevicesView()
                .navigationTitle("All Devices")
        }
    }
}

struct WebHistoryTab: View {
    var body: some View {
        NavigationStack {
            WebHistoryView()
                .navigationTitle("Web History")
        }
    }
}

struct SettingsTab: View {
    var body: some View {
        NavigationStack {
            IOSSettingsView()
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(IOSAppState())
}
