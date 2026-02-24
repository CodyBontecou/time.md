import Foundation
import FamilyControls
import Combine

/// Service for managing Screen Time (FamilyControls) authorization
@MainActor
final class AuthorizationService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var authorizationStatus: ScreenTimeAuthStatus = .notDetermined
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let authCenter = AuthorizationCenter.shared
    
    // MARK: - Initialization
    
    init() {
        // Observe authorization status changes from the system
        observeAuthorizationStatus()
        
        // Check current status on init
        Task {
            await checkCurrentStatus()
        }
    }
    
    // MARK: - Public Methods
    
    /// Request Screen Time authorization from the user
    /// Shows system dialog for user to approve access
    func requestAuthorization() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Request authorization for individual use (personal tracking, not parental controls)
            try await authCenter.requestAuthorization(for: .individual)
            
            // Authorization granted
            authorizationStatus = .approved
            isAuthorized = true
            
            // Store successful authorization timestamp
            UserDefaults.standard.set(Date(), forKey: Keys.lastAuthorizationDate)
            
        } catch {
            handleFamilyControlsError(error)
        }
        
        isLoading = false
    }
    
    /// Check current authorization status without prompting user
    func checkCurrentStatus() async {
        let status = authCenter.authorizationStatus
        
        switch status {
        case .approved:
            authorizationStatus = .approved
            isAuthorized = true
        case .denied:
            authorizationStatus = .denied
            isAuthorized = false
        case .notDetermined:
            authorizationStatus = .notDetermined
            isAuthorized = false
        @unknown default:
            authorizationStatus = .notDetermined
            isAuthorized = false
        }
    }
    
    /// Revoke authorization (user must go to Settings to actually revoke)
    func revokeAuthorization() async {
        authorizationStatus = .denied
        isAuthorized = false
        
        // Note: FamilyControls doesn't have a programmatic revoke
        // User must go to Settings > Screen Time to revoke access
        errorMessage = "To revoke Screen Time access, please go to Settings > Screen Time"
    }
    
    // MARK: - Private Methods
    
    private func observeAuthorizationStatus() {
        // FamilyControls publishes status changes
        authCenter.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateFromSystemStatus(status)
            }
            .store(in: &cancellables)
    }
    
    private func updateFromSystemStatus(_ status: FamilyControls.AuthorizationStatus) {
        switch status {
        case .approved:
            authorizationStatus = .approved
            isAuthorized = true
        case .denied:
            authorizationStatus = .denied
            isAuthorized = false
        case .notDetermined:
            authorizationStatus = .notDetermined
            isAuthorized = false
        @unknown default:
            authorizationStatus = .notDetermined
            isAuthorized = false
        }
    }
    
    private func handleFamilyControlsError(_ error: Error) {
        authorizationStatus = .denied
        isAuthorized = false
        
        // Parse error description for user-friendly messages
        let errorString = error.localizedDescription.lowercased()
        
        if errorString.contains("restricted") {
            errorMessage = "Screen Time access is restricted on this device. Check parental controls or device management settings."
        } else if errorString.contains("unavailable") {
            errorMessage = "Screen Time is not available on this device."
        } else if errorString.contains("cancel") {
            // User cancelled - not really an error
            errorMessage = nil
        } else if errorString.contains("network") {
            authorizationStatus = .notDetermined
            errorMessage = "Network error. Please check your connection and try again."
        } else {
            errorMessage = "Failed to request Screen Time access. Please try again."
        }
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let lastAuthorizationDate = "com.codybontecou.Timeprint.lastAuthorizationDate"
    }
}

// MARK: - Screen Time Authorization Status

/// Custom authorization status for app use (renamed to avoid conflict with FamilyControls)
enum ScreenTimeAuthStatus: String, Sendable {
    case notDetermined
    case approved
    case denied
    
    var displayName: String {
        switch self {
        case .notDetermined:
            return "Not Requested"
        case .approved:
            return "Authorized"
        case .denied:
            return "Denied"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .notDetermined:
            return "questionmark.circle"
        case .approved:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        }
    }
    
    var statusColor: String {
        switch self {
        case .notDetermined:
            return "gray"
        case .approved:
            return "green"
        case .denied:
            return "red"
        }
    }
}
