import AppKit
import Foundation

/// Reads the active tab URL+title from supported browsers via AppleScript /
/// Apple Events. Sandbox-compatible given the `com.apple.security.automation.apple-events`
/// entitlement; macOS prompts the user the first time we contact each browser.
enum BrowserTabSampler {

    enum Dialect {
        case safari      // `current tab of front window`
        case chromium    // `active tab of front window`
    }

    struct Browser {
        let bundleID: String
        let appleScriptName: String
        let dialect: Dialect
    }

    /// Bundle IDs we know how to sample. Firefox isn't here — it doesn't expose
    /// active tab properties via AppleScript.
    static let supported: [Browser] = [
        Browser(bundleID: "com.apple.Safari",                appleScriptName: "Safari",                  dialect: .safari),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", appleScriptName: "Safari Technology Preview", dialect: .safari),
        Browser(bundleID: "com.google.Chrome",               appleScriptName: "Google Chrome",           dialect: .chromium),
        Browser(bundleID: "com.google.Chrome.canary",        appleScriptName: "Google Chrome Canary",    dialect: .chromium),
        Browser(bundleID: "company.thebrowser.Browser",      appleScriptName: "Arc",                     dialect: .chromium),
        Browser(bundleID: "com.brave.Browser",               appleScriptName: "Brave Browser",           dialect: .chromium),
        Browser(bundleID: "com.brave.Browser.beta",          appleScriptName: "Brave Browser Beta",      dialect: .chromium),
        Browser(bundleID: "com.microsoft.edgemac",           appleScriptName: "Microsoft Edge",          dialect: .chromium),
        Browser(bundleID: "com.vivaldi.Vivaldi",             appleScriptName: "Vivaldi",                 dialect: .chromium),
        Browser(bundleID: "com.operasoftware.Opera",         appleScriptName: "Opera",                   dialect: .chromium),
    ]

    static func browser(for bundleID: String) -> Browser? {
        supported.first { $0.bundleID == bundleID }
    }

    static func isSupportedBrowser(bundleID: String) -> Bool {
        browser(for: bundleID) != nil
    }

    struct Tab {
        let url: String
        let title: String
        let domain: String
    }

    private static let separator = "|||TIMEMDSEP|||"

    /// Returns the active tab for `browser`, or nil if AppleScript failed,
    /// the user denied automation, or no window is open.
    static func currentTab(for browser: Browser) -> Tab? {
        let property = browser.dialect == .safari ? "current tab" : "active tab"
        let source = """
        tell application "\(browser.appleScriptName)"
            if (count of windows) is 0 then return ""
            set theURL to URL of \(property) of front window
            set theTitle to (name of \(property) of front window) as text
            return theURL & "\(separator)" & theTitle
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if error != nil { return nil }
        guard let combined = descriptor.stringValue, !combined.isEmpty else { return nil }

        let parts = combined.components(separatedBy: separator)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }

        let url = parts[0]
        let title = parts[1]
        guard let domain = domain(from: url) else { return nil }
        return Tab(url: url, title: title, domain: domain)
    }

    /// Extracts a hostname suitable for grouping. Strips a single leading
    /// `www.`. Returns nil for non-HTTP(S) URLs (chrome://, file://, etc.).
    static func domain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(),
              !host.isEmpty
        else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }
}
