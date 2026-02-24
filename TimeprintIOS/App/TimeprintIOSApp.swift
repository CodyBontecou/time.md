import SwiftUI

@main
struct TimeprintIOSApp: App {
    @StateObject private var appState = IOSAppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

/// Root content view with adaptive navigation (tabs on iPhone, sidebar on iPad)
struct ContentView: View {
    @EnvironmentObject private var appState: IOSAppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab = 0
    @State private var selectedDestination: NavigationDestination? = .overview
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
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
            .navigationTitle("Timeprint")
        } detail: {
            switch selectedDestination {
            case .overview:
                CompactOverviewView()
                    .navigationTitle("Overview")
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
                    .navigationTitle("Overview")
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
                .navigationTitle("Overview")
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
