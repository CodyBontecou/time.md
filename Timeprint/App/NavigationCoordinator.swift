import Foundation
import Observation

/// Shared navigation state to allow any child view to trigger sidebar navigation.
@Observable
final class NavigationCoordinator {
    var selectedDestination: NavigationDestination? = .overview
}
