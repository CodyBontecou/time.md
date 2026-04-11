#if !APPSTORE
import Sparkle
#endif
import SwiftUI

#if os(macOS)
/// Keyboard shortcuts and menu commands for time.md
struct TimeMdCommands: Commands {
    var navigation: NavigationCoordinator
    var filters: GlobalFilterStore
    let performCloudSync: () async -> Void
    #if !APPSTORE
    @ObservedObject var updaterController: UpdaterController
    #endif
    @AppStorage("showMenuBarItem") private var showMenuBarItem: Bool = true

    var body: some Commands {
        #if !APPSTORE
        // Check for Updates in App menu
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                updaterController.checkForUpdates()
            }
            .disabled(!updaterController.canCheckForUpdates)
        }
        #endif
        
        // Replace default "New" command group
        CommandGroup(replacing: .newItem) {
            // No new document creation in time.md
        }
        
        // View menu - Navigation shortcuts
        CommandGroup(after: .toolbar) {
            Section {
                Button("Toggle Sidebar") {
                    navigation.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)
                
                Divider()
                
                Button("Overview") {
                    navigation.selectedDestination = .overview
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Calendar") {
                    navigation.selectedDestination = .calendar
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Trends") {
                    navigation.selectedDestination = .trends
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button("Apps & Categories") {
                    navigation.selectedDestination = .appsCategories
                }
                .keyboardShortcut("4", modifiers: .command)
                
                Button("Sessions") {
                    navigation.selectedDestination = .sessions
                }
                .keyboardShortcut("5", modifiers: .command)
                
                Button("Heatmap") {
                    navigation.selectedDestination = .heatmap
                }
                .keyboardShortcut("6", modifiers: .command)
                
                Divider()
                
                Button("Web History") {
                    navigation.selectedDestination = .webHistory
                }
                .keyboardShortcut("7", modifiers: .command)
                
                Button("Exports") {
                    navigation.selectedDestination = .exports
                }
                .keyboardShortcut("8", modifiers: .command)
                
                Divider()
                
                Button("Settings") {
                    navigation.selectedDestination = .settings
                }
                .keyboardShortcut("9", modifiers: .command)
                
                Divider()
                
                Toggle("Show Menu Bar Item", isOn: $showMenuBarItem)
            }
        }
        
        // Time range shortcuts
        CommandMenu("Time Range") {
            Button("Today") {
                setGranularity(.day)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            
            Button("This Week") {
                setGranularity(.week)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            
            Button("This Month") {
                setGranularity(.month)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            
            Button("This Year") {
                setGranularity(.year)
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Previous Period") {
                navigatePrevious()
            }
            .keyboardShortcut("[", modifiers: .command)
            
            Button("Next Period") {
                navigateNext()
            }
            .keyboardShortcut("]", modifiers: .command)
            
            Button("Jump to Today") {
                jumpToToday()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
        }
        
        // Sync commands
        CommandMenu("Sync") {
            Button("Sync Now") {
                Task {
                    await performCloudSync()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Button("Force Local Sync") {
                Task.detached {
                    HistoryStore.forceSync()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
    
    // MARK: - Time Navigation
    
    private func setGranularity(_ granularity: TimeGranularity) {
        withAnimation(.easeInOut(duration: 0.2)) {
            filters.granularity = granularity
            filters.adjustDateRange(for: granularity)
        }
    }
    
    private func navigatePrevious() {
        withAnimation(.easeInOut(duration: 0.2)) {
            filters.stepBackward()
        }
    }
    
    private func navigateNext() {
        withAnimation(.easeInOut(duration: 0.2)) {
            filters.stepForward()
        }
    }
    
    private func jumpToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            filters.goToToday()
        }
    }
}

// MARK: - Keyboard Shortcut Reference

/*
 TIMEPRINT KEYBOARD SHORTCUTS
 ============================
 
 Navigation:
 ⌘B          Toggle Sidebar
 ⌘1          Overview
 ⌘2          Calendar
 ⌘3          Trends
 ⌘4          Apps & Categories
 ⌘5          Sessions
 ⌘6          Heatmap
 ⌘7          Web History
 ⌘8          Exports
 ⌘9          Settings
 
 View:
 (toggle)    Show Menu Bar Item
 
 Time Range:
 ⇧⌘T         Today
 ⇧⌘W         This Week
 ⇧⌘M         This Month
 ⇧⌘Y         This Year
 ⌘[          Previous Period
 ⌘]          Next Period
 ⇧⌘J         Jump to Today
 
 Sync:
 ⌘R          Sync Now (iCloud)
 ⇧⌘R         Force Local Sync
 
 Standard:
 ⌘Q          Quit
 ⌘W          Close Window
 ⌘M          Minimize
 ⌘H          Hide
 */
#endif
