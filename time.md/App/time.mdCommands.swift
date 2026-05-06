import SwiftUI

#if os(macOS)
import Sparkle

/// Keyboard shortcuts and menu commands for time.md
struct TimeMdCommands: Commands {
    var navigation: NavigationCoordinator
    var filters: GlobalFilterStore
    var updater: SPUUpdater
    @AppStorage(AppVisibilityMode.storageKey) private var visibilityModeRaw: String = AppVisibilityMode.dockAndMenuBar.rawValue

    private var visibilityMode: AppVisibilityMode {
        AppVisibilityMode(rawValue: visibilityModeRaw) ?? .dockAndMenuBar
    }

    var body: some Commands {
        // Replace default "New" command group
        CommandGroup(replacing: .newItem) {
            // No new document creation in time.md
        }

        // App menu - "Check for Updates…" sits right under "About time.md"
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updater)
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

                Button("Review") {
                    navigation.selectedDestination = .review
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Details") {
                    navigation.selectedDestination = .details
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Projects") {
                    navigation.selectedDestination = .projects
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Rules") {
                    navigation.selectedDestination = .rules
                }
                .keyboardShortcut("5", modifiers: .command)

                Divider()

                Button("Web History") {
                    navigation.selectedDestination = .webHistory
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Reports") {
                    navigation.selectedDestination = .reports
                }
                .keyboardShortcut("7", modifiers: .command)
                
                Divider()
                
                Button("Settings") {
                    navigation.selectedDestination = .settings
                }
                .keyboardShortcut("8", modifiers: .command)
                
                Divider()

                Menu("Visibility") {
                    ForEach(AppVisibilityMode.allCases) { mode in
                        Button {
                            visibilityModeRaw = mode.rawValue
                        } label: {
                            if visibilityMode == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }
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
 ⌘2          Review
 ⌘3          Details
 ⌘4          Projects
 ⌘5          Rules
 ⌘6          Web History
 ⌘7          Reports
 ⌘8          Settings
 
 View:
 (submenu)   Visibility (Dock + Menu Bar / Menu Bar Only / Dock Only / Hidden)
 
 Time Range:
 ⇧⌘T         Today
 ⇧⌘W         This Week
 ⇧⌘M         This Month
 ⇧⌘Y         This Year
 ⌘[          Previous Period
 ⌘]          Next Period
 ⇧⌘J         Jump to Today

 Standard:
 ⌘Q          Quit
 ⌘W          Close Window
 ⌘M          Minimize
 ⌘H          Hide
 */
#endif
