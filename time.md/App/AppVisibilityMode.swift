import AppKit
import SwiftUI

/// Controls where time.md surfaces in the macOS UI.
///
/// macOS couples the Dock icon and Cmd-Tab entry under a single
/// `NSApplication.ActivationPolicy`, so they must be toggled together:
/// `.regular` shows both, `.accessory` hides both. The menu bar item is
/// independent and toggled via the `MenuBarExtra` scene.
enum AppVisibilityMode: String, CaseIterable, Identifiable {
    case dockAndMenuBar
    case menuBarOnly
    case dockOnly
    case hidden

    var id: String { rawValue }

    static let storageKey = "appVisibilityMode"

    var title: String {
        switch self {
        case .dockAndMenuBar: return "Dock + Menu Bar"
        case .menuBarOnly: return "Menu Bar Only"
        case .dockOnly: return "Dock Only"
        case .hidden: return "Hidden"
        }
    }

    var summary: String {
        switch self {
        case .dockAndMenuBar: return "Dock icon, Cmd-Tab, and menu bar"
        case .menuBarOnly: return "Menu bar only — hidden from Dock and Cmd-Tab"
        case .dockOnly: return "Dock icon and Cmd-Tab — no menu bar"
        case .hidden: return "Invisible — reopen from Spotlight or Finder"
        }
    }

    var systemImage: String {
        switch self {
        case .dockAndMenuBar: return "macwindow.on.rectangle"
        case .menuBarOnly: return "menubar.rectangle"
        case .dockOnly: return "dock.rectangle"
        case .hidden: return "eye.slash"
        }
    }

    var showsMenuBar: Bool {
        switch self {
        case .dockAndMenuBar, .menuBarOnly: return true
        case .dockOnly, .hidden: return false
        }
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .dockAndMenuBar, .dockOnly: return .regular
        case .menuBarOnly, .hidden: return .accessory
        }
    }

    static var current: AppVisibilityMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return AppVisibilityMode(rawValue: raw) ?? .dockAndMenuBar
    }

    /// Applies the activation policy on the next runloop tick. Calling
    /// `setActivationPolicy` synchronously from inside SwiftUI's update
    /// cycle (e.g. from a view's `.onChange` or a button action that
    /// reflows windows) can crash `NSHostingView`'s constraint pass.
    func apply() {
        let target = activationPolicy
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != target {
                NSApp.setActivationPolicy(target)
            }
        }
    }

    /// Synchronous variant for use from `applicationDidFinishLaunching`,
    /// before any SwiftUI window has been laid out.
    func applyImmediately() {
        if NSApp.activationPolicy() != activationPolicy {
            NSApp.setActivationPolicy(activationPolicy)
        }
    }
}
