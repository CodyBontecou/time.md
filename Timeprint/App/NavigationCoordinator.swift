import Foundation
import Observation
import SwiftUI

/// Shared navigation state to allow any child view to trigger sidebar navigation.
@Observable
final class NavigationCoordinator {
    var selectedDestination: NavigationDestination? = .overview
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    
    /// Toggle sidebar visibility between shown and hidden
    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}
