import SwiftUI

#if os(macOS)
/// Keyboard shortcuts and menu commands for Timeprint
struct TimeprintCommands: Commands {
    var navigation: NavigationCoordinator
    var filters: GlobalFilterStore
    let performCloudSync: () async -> Void
    
    var body: some Commands {
        // Replace default "New" command group
        CommandGroup(replacing: .newItem) {
            // No new document creation in Timeprint
        }
        
        // View menu - Navigation shortcuts
        CommandGroup(after: .toolbar) {
            Section {
                Button("Overview") {
                    navigation.selectedDestination = .overview
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Trends") {
                    navigation.selectedDestination = .trends
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Apps & Categories") {
                    navigation.selectedDestination = .appsCategories
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button("Sessions") {
                    navigation.selectedDestination = .sessions
                }
                .keyboardShortcut("4", modifiers: .command)
                
                Button("Heatmap") {
                    navigation.selectedDestination = .heatmap
                }
                .keyboardShortcut("5", modifiers: .command)
                
                Divider()
                
                Button("Exports") {
                    navigation.selectedDestination = .exports
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                
                Button("Settings") {
                    navigation.selectedDestination = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
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
        let calendar = Calendar.current
        let component: Calendar.Component
        
        switch filters.granularity {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .year:
            component = .year
        }
        
        if let newStart = calendar.date(byAdding: component, value: -1, to: filters.startDate),
           let newEnd = calendar.date(byAdding: component, value: -1, to: filters.endDate) {
            withAnimation {
                filters.startDate = newStart
                filters.endDate = newEnd
            }
        }
    }
    
    private func navigateNext() {
        let calendar = Calendar.current
        let component: Calendar.Component
        
        switch filters.granularity {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .year:
            component = .year
        }
        
        if let newStart = calendar.date(byAdding: component, value: 1, to: filters.startDate),
           let newEnd = calendar.date(byAdding: component, value: 1, to: filters.endDate) {
            // Don't go past today
            guard newEnd <= Date() else { return }
            withAnimation {
                filters.startDate = newStart
                filters.endDate = newEnd
            }
        }
    }
    
    private func jumpToToday() {
        withAnimation {
            filters.adjustDateRange(for: filters.granularity)
        }
    }
}

// MARK: - Keyboard Shortcut Reference

/*
 TIMEPRINT KEYBOARD SHORTCUTS
 ============================
 
 Navigation:
 ⌘1          Overview
 ⌘2          Trends
 ⌘3          Apps & Categories
 ⌘4          Sessions
 ⌘5          Heatmap
 ⇧⌘E         Exports
 ⌘,          Settings
 
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
