import Foundation

/// Manages a macOS Launch Agent that syncs Screen Time data from knowledgeC.db
/// into the persistent Timeprint history database every 4 hours, even when the
/// app isn't running.
///
/// The agent plist is written dynamically to `~/Library/LaunchAgents/` with the
/// current executable path and an `AssociatedBundleIdentifiers` key so macOS
/// shows **"Timeprint"** (not the generic developer name) in the background-
/// activity notification and in System Settings → Login Items & Extensions.
enum BackgroundSyncManager {
    private static let agentLabel = "bontecou.Timeprint.BackgroundSync"

    // MARK: - Public

    /// Install or update the background sync Launch Agent.
    /// Safe to call on every launch — updates the plist with the current
    /// executable path and reloads the agent. Non-fatal on failure.
    static func install() {
        do {
            try writeLaunchAgentPlist()
            reloadAgent()
        } catch {
            print("[BackgroundSync] Installation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Launch Agent plist

    private static func launchAgentURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private static func writeLaunchAgentPlist() throws {
        guard let executablePath = Bundle.main.executablePath else {
            print("[BackgroundSync] Could not determine executable path")
            return
        }

        let plistURL = launchAgentURL()

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executablePath, "--background-sync"],
            "StartInterval": 14400,                    // every 4 hours
            "RunAtLoad": true,                         // also run at login
            "AssociatedBundleIdentifiers": [            // brands the notification
                "bontecou.Timeprint",                  // and System Settings entry
            ],                                         // with the Timeprint name/icon
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null",
        ]

        let agentsDir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    // MARK: - launchctl

    private static func reloadAgent() {
        let plistPath = launchAgentURL().path

        // Unload first (safe even if not currently loaded).
        run("/bin/launchctl", arguments: ["unload", plistPath])

        // Load the (possibly updated) agent.
        run("/bin/launchctl", arguments: ["load", plistPath])
    }

    @discardableResult
    private static func run(_ path: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
