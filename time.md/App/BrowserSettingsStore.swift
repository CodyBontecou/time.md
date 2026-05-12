import Foundation
import SwiftUI

/// Manages which browsers are enabled for web history tracking.
/// Settings are persisted via UserDefaults.
@Observable
final class BrowserSettingsStore: @unchecked Sendable {
    
    static let shared = BrowserSettingsStore()
    
    private let defaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let safariEnabled = "browser.safari.enabled"
        static let chromeEnabled = "browser.chrome.enabled"
        static let firefoxEnabled = "browser.firefox.enabled"
        static let arcEnabled = "browser.arc.enabled"
        static let braveEnabled = "browser.brave.enabled"
        static let edgeEnabled = "browser.edge.enabled"
        static let webHistoryPersistenceEnabled = WebHistoryArchiveStore.enabledKey
    }
    
    // MARK: - Browser Enable States
    
    var safariEnabled: Bool {
        didSet { defaults.set(safariEnabled, forKey: Keys.safariEnabled) }
    }
    
    var chromeEnabled: Bool {
        didSet { defaults.set(chromeEnabled, forKey: Keys.chromeEnabled) }
    }

    var firefoxEnabled: Bool {
        didSet { defaults.set(firefoxEnabled, forKey: Keys.firefoxEnabled) }
    }
    
    var arcEnabled: Bool {
        didSet { defaults.set(arcEnabled, forKey: Keys.arcEnabled) }
    }
    
    var braveEnabled: Bool {
        didSet { defaults.set(braveEnabled, forKey: Keys.braveEnabled) }
    }
    
    var edgeEnabled: Bool {
        didSet { defaults.set(edgeEnabled, forKey: Keys.edgeEnabled) }
    }

    var webHistoryPersistenceEnabled: Bool {
        didSet {
            defaults.set(webHistoryPersistenceEnabled, forKey: Keys.webHistoryPersistenceEnabled)
            WebHistoryArchiveStore.setEnabled(webHistoryPersistenceEnabled)
            WebHistoryArchiveScheduler.shared.updateForCurrentSettings()
            if webHistoryPersistenceEnabled {
                Task.detached(priority: .utility) {
                    await SQLiteBrowsingHistoryService().snapshotRecentHistoryForPersistence(days: 90)
                }
            }
        }
    }
    
    // MARK: - Init
    
    private init() {
        // Default all browsers to enabled if no setting exists
        if defaults.object(forKey: Keys.safariEnabled) == nil {
            defaults.set(true, forKey: Keys.safariEnabled)
        }
        if defaults.object(forKey: Keys.chromeEnabled) == nil {
            defaults.set(true, forKey: Keys.chromeEnabled)
        }
        if defaults.object(forKey: Keys.firefoxEnabled) == nil {
            defaults.set(true, forKey: Keys.firefoxEnabled)
        }
        if defaults.object(forKey: Keys.arcEnabled) == nil {
            defaults.set(true, forKey: Keys.arcEnabled)
        }
        if defaults.object(forKey: Keys.braveEnabled) == nil {
            defaults.set(true, forKey: Keys.braveEnabled)
        }
        if defaults.object(forKey: Keys.edgeEnabled) == nil {
            defaults.set(true, forKey: Keys.edgeEnabled)
        }
        
        // Load current values
        self.safariEnabled = defaults.bool(forKey: Keys.safariEnabled)
        self.chromeEnabled = defaults.bool(forKey: Keys.chromeEnabled)
        self.firefoxEnabled = defaults.bool(forKey: Keys.firefoxEnabled)
        self.arcEnabled = defaults.bool(forKey: Keys.arcEnabled)
        self.braveEnabled = defaults.bool(forKey: Keys.braveEnabled)
        self.edgeEnabled = defaults.bool(forKey: Keys.edgeEnabled)
        self.webHistoryPersistenceEnabled = defaults.bool(forKey: Keys.webHistoryPersistenceEnabled)
        WebHistoryArchiveScheduler.shared.updateForCurrentSettings()
    }
    
    // MARK: - Helpers
    
    /// Check if a specific browser is enabled
    func isEnabled(_ browser: BrowserSource) -> Bool {
        switch browser {
        case .all: return true
        case .safari: return safariEnabled
        case .chrome: return chromeEnabled
        case .firefox: return firefoxEnabled
        case .arc: return arcEnabled
        case .brave: return braveEnabled
        case .edge: return edgeEnabled
        }
    }
    
    /// Toggle a specific browser
    func toggle(_ browser: BrowserSource) {
        switch browser {
        case .all: break // Cannot toggle "all"
        case .safari: safariEnabled.toggle()
        case .chrome: chromeEnabled.toggle()
        case .firefox: firefoxEnabled.toggle()
        case .arc: arcEnabled.toggle()
        case .brave: braveEnabled.toggle()
        case .edge: edgeEnabled.toggle()
        }
    }
    
    /// Set enabled state for web history persistence.
    func setWebHistoryPersistenceEnabled(_ enabled: Bool) {
        webHistoryPersistenceEnabled = enabled
    }

    /// Set enabled state for a specific browser
    func setEnabled(_ browser: BrowserSource, enabled: Bool) {
        switch browser {
        case .all: break // Cannot set "all"
        case .safari: safariEnabled = enabled
        case .chrome: chromeEnabled = enabled
        case .firefox: firefoxEnabled = enabled
        case .arc: arcEnabled = enabled
        case .brave: braveEnabled = enabled
        case .edge: edgeEnabled = enabled
        }
    }
    
    /// Get list of enabled browsers from available browsers
    func enabledBrowsers(from available: [BrowserSource]) -> [BrowserSource] {
        var result: [BrowserSource] = []
        
        for browser in available {
            if browser == .all {
                // Only include "All" if there are multiple enabled browsers
                continue
            }
            if isEnabled(browser) {
                result.append(browser)
            }
        }
        
        // Add "All" at the beginning if multiple browsers are enabled
        if result.count > 1 {
            result.insert(.all, at: 0)
        }
        
        return result
    }
    
    /// Get all browsers with their installation and enabled status
    func allBrowsersStatus() -> [(browser: BrowserSource, isInstalled: Bool, isEnabled: Bool)] {
        let allBrowsers: [BrowserSource] = [.safari, .chrome, .firefox, .arc, .brave, .edge]
        let service = SQLiteBrowsingHistoryService()
        let installed = Set(service.availableBrowsers())
        
        return allBrowsers.map { browser in
            (browser: browser, isInstalled: installed.contains(browser), isEnabled: isEnabled(browser))
        }
    }
}
