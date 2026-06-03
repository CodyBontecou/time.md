import Darwin
import Foundation

enum DomainBlockHelperInstallState: String, Codable, Sendable {
    case notInstalled
    case installed
    case needsUpgrade
    case unavailable
}

struct DomainBlockHelperStatus: Codable, Hashable, Sendable {
    var installState: DomainBlockHelperInstallState
    var helperVersion: String?
    var appVersion: String?
    var activeDomains: [String]
    var lastAppliedAt: Date?
    var lastErrorDescription: String?

    static let unavailable = DomainBlockHelperStatus(
        installState: .unavailable,
        helperVersion: nil,
        appVersion: nil,
        activeDomains: [],
        lastAppliedAt: nil,
        lastErrorDescription: nil
    )
}

struct DomainBlockHelperApplyResult: Codable, Hashable, Sendable {
    var status: DomainBlockHelperStatus
    var changedHosts: Bool
    var changedPFAnchor: Bool
    var commandOutput: [String]
}

enum DomainBlockHelperError: LocalizedError, Equatable, Sendable {
    case authorizationDenied
    case helperUnavailable(String)
    case versionMismatch(app: String?, helper: String?)
    case hostsFileNotUTF8
    case hostsFileTooLarge(Int)
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case commandFailed(command: String, exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Administrator approval is required to install or update the time.md domain blocking helper."
        case let .helperUnavailable(reason):
            return "The time.md domain blocking helper is unavailable: \(reason)"
        case let .versionMismatch(app, helper):
            return "The time.md domain blocking helper needs an update. App version: \(app ?? "unknown"), helper version: \(helper ?? "unknown")."
        case .hostsFileNotUTF8:
            return "The hosts file is not valid UTF-8, so time.md will not modify it automatically."
        case let .hostsFileTooLarge(size):
            return "The hosts file is unexpectedly large (\(size) bytes), so time.md will not modify it automatically."
        case let .fileReadFailed(path):
            return "Unable to read \(path)."
        case let .fileWriteFailed(path):
            return "Unable to write \(path)."
        case let .commandFailed(command, exitCode, output):
            return "Command failed (\(exitCode)): \(command)\n\(output)"
        }
    }
}

protocol DomainBlockHelperClient: Sendable {
    func status() async -> DomainBlockHelperStatus
    func installOrUpgrade(withConsent consent: DomainBlockUserConsent) async throws -> DomainBlockHelperStatus
    func apply(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult
    func clearAll() async throws -> DomainBlockHelperApplyResult
    func repair(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult
    func uninstall(withConsent consent: DomainBlockUserConsent) async throws
}

/// Explicit consent payload passed to helper operations that can require admin
/// privileges. UI code should show `message` before invoking the real helper;
/// tests and the fake helper can assert denied/cancelled flows without touching
/// system files.
struct DomainBlockUserConsent: Codable, Hashable, Sendable {
    var approved: Bool
    var message: String

    static let denied = DomainBlockUserConsent(approved: false, message: "User denied helper authorization.")
    static let approvedForDomainBlocking = DomainBlockUserConsent(
        approved: true,
        message: "time.md will add only its marked block to /etc/hosts, load its own pf anchor, and preserve all unrelated system configuration."
    )
}

actor FakeDomainBlockHelperClient: DomainBlockHelperClient {
    private(set) var installed = false
    private(set) var currentPlan: DomainBlockCompiledRules?
    private var lastAppliedAt: Date?
    private var lastErrorDescription: String?
    var simulatedApplyError: DomainBlockHelperError?
    var helperVersion: String?
    var appVersion: String?

    private let compiler: DomainBlockRuleCompiler

    nonisolated init(
        installed: Bool = false,
        helperVersion: String? = nil,
        appVersion: String? = nil,
        compiler: DomainBlockRuleCompiler = DomainBlockRuleCompiler()
    ) {
        self.installed = installed
        self.helperVersion = helperVersion
        self.appVersion = appVersion
        self.compiler = compiler
    }

    func status() async -> DomainBlockHelperStatus {
        DomainBlockHelperStatus(
            installState: installState,
            helperVersion: helperVersion,
            appVersion: appVersion,
            activeDomains: currentPlan?.desiredState.domains ?? [],
            lastAppliedAt: lastAppliedAt,
            lastErrorDescription: lastErrorDescription
        )
    }

    func installOrUpgrade(withConsent consent: DomainBlockUserConsent) async throws -> DomainBlockHelperStatus {
        guard consent.approved else {
            lastErrorDescription = DomainBlockHelperError.authorizationDenied.localizedDescription
            throw DomainBlockHelperError.authorizationDenied
        }
        installed = true
        helperVersion = appVersion
        return await status()
    }

    func apply(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult {
        guard installed else { throw DomainBlockHelperError.helperUnavailable("Helper is not installed.") }
        if installState == .needsUpgrade { throw DomainBlockHelperError.versionMismatch(app: appVersion, helper: helperVersion) }
        if let simulatedApplyError {
            lastErrorDescription = simulatedApplyError.localizedDescription
            throw simulatedApplyError
        }

        let newPlan = compiler.compile(desiredState: desiredState)
        let changedHosts = Set(newPlan.hostEntries) != Set(currentPlan?.hostEntries ?? [])
        let changedPF = newPlan.pfAnchorRules != currentPlan?.pfAnchorRules
        currentPlan = newPlan
        lastAppliedAt = desiredState.generatedAt
        lastErrorDescription = nil
        return DomainBlockHelperApplyResult(status: await status(), changedHosts: changedHosts, changedPFAnchor: changedPF, commandOutput: [])
    }

    func clearAll() async throws -> DomainBlockHelperApplyResult {
        try await apply(try DomainBlockDesiredState(domains: [], generatedAt: Date()))
    }

    func repair(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult {
        try await apply(desiredState)
    }

    func uninstall(withConsent consent: DomainBlockUserConsent) async throws {
        guard consent.approved else { throw DomainBlockHelperError.authorizationDenied }
        installed = false
        currentPlan = nil
        lastAppliedAt = nil
    }

    private var installState: DomainBlockHelperInstallState {
        guard installed else { return .notInstalled }
        if helperVersion != appVersion { return .needsUpgrade }
        return .installed
    }
}

struct DomainBlockSystemPaths: Sendable {
    var hostsURL: URL
    var pfAnchorURL: URL

    nonisolated init(
        hostsURL: URL = URL(fileURLWithPath: "/etc/hosts"),
        pfAnchorURL: URL = URL(fileURLWithPath: "/etc/pf.anchors/\(DomainBlockRuleCompiler.pfAnchorName)")
    ) {
        self.hostsURL = hostsURL
        self.pfAnchorURL = pfAnchorURL
    }
}

protocol DomainBlockCommandRunning: Sendable {
    func run(_ launchPath: String, arguments: [String]) async throws -> String
}

struct ProcessDomainBlockCommandRunner: DomainBlockCommandRunning {
    nonisolated init() {}

    func run(_ launchPath: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw DomainBlockHelperError.commandFailed(
                    command: ([launchPath] + arguments).joined(separator: " "),
                    exitCode: process.terminationStatus,
                    output: output
                )
            }
            return output
        }.value
    }
}

struct DomainBlockLaunchDaemonConfiguration: Sendable {
    static let currentHelperVersion = "2"
    static let defaultLabel = "com.bontecou.time-md.domain-block-helper"

    var label: String
    var helperVersion: String
    var stateDirectoryURL: URL
    var helperScriptURL: URL
    var launchDaemonPlistURL: URL

    init(
        label: String = Self.defaultLabel,
        helperVersion: String = Self.currentHelperVersion,
        stateDirectoryURL: URL = Self.defaultStateDirectoryURL(),
        helperScriptURL: URL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(Self.defaultLabel)"),
        launchDaemonPlistURL: URL = URL(fileURLWithPath: "/Library/LaunchDaemons/\(Self.defaultLabel).plist")
    ) {
        self.label = label
        self.helperVersion = helperVersion
        self.stateDirectoryURL = stateDirectoryURL
        self.helperScriptURL = helperScriptURL
        self.launchDaemonPlistURL = launchDaemonPlistURL
    }

    private static func defaultStateDirectoryURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/time.md/DomainBlockHelper", isDirectory: true)
    }

    var triggerURL: URL { stateDirectoryURL.appendingPathComponent("request.trigger") }
    var statusURL: URL { stateDirectoryURL.appendingPathComponent("status.env") }
    var activeDomainsURL: URL { stateDirectoryURL.appendingPathComponent("active-domains") }
    var helperLogURL: URL { stateDirectoryURL.appendingPathComponent("helper.out.log") }
    var helperErrorLogURL: URL { stateDirectoryURL.appendingPathComponent("helper.err.log") }
}

private struct DomainBlockLaunchDaemonStatus: Sendable {
    var requestID: String?
    var result: String?
    var helperVersion: String?
    var appVersion: String?
    var activeDomains: [String]
    var generatedAt: Date?
    var changedHosts: Bool
    var changedPFAnchor: Bool
    var lastErrorDescription: String?
}

/// App-side client backed by a one-time installed LaunchDaemon. Installation is
/// the only operation that asks for administrator approval; subsequent domain
/// changes are staged into the user's Application Support folder and applied by
/// the root LaunchDaemon when its trigger file changes.
actor PrivilegedDomainBlockHelperClient: DomainBlockHelperClient {
    static let shared = PrivilegedDomainBlockHelperClient()

    private let paths: DomainBlockSystemPaths
    private let compiler: DomainBlockRuleCompiler
    private let configuration: DomainBlockLaunchDaemonConfiguration
    private var lastStatus: DomainBlockHelperStatus

    init(
        paths: DomainBlockSystemPaths = DomainBlockSystemPaths(),
        compiler: DomainBlockRuleCompiler = DomainBlockRuleCompiler(),
        configuration: DomainBlockLaunchDaemonConfiguration = DomainBlockLaunchDaemonConfiguration()
    ) {
        self.paths = paths
        self.compiler = compiler
        self.configuration = configuration
        self.lastStatus = DomainBlockHelperStatus(
            installState: .notInstalled,
            helperVersion: nil,
            appVersion: Self.currentAppVersion,
            activeDomains: [],
            lastAppliedAt: nil,
            lastErrorDescription: nil
        )
    }

    func status() async -> DomainBlockHelperStatus {
        let refreshed = loadStatus()
        lastStatus = refreshed
        return refreshed
    }

    func installOrUpgrade(withConsent consent: DomainBlockUserConsent) async throws -> DomainBlockHelperStatus {
        guard consent.approved else { throw DomainBlockHelperError.authorizationDenied }
        do {
            try ensureStateDirectoryExists()
            try await installLaunchDaemon()
            lastStatus = loadStatus()
            return lastStatus
        } catch let error as DomainBlockHelperError {
            lastStatus.lastErrorDescription = error.localizedDescription
            throw error
        } catch {
            lastStatus.lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    func apply(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult {
        let plan = compiler.compile(desiredState: desiredState)
        return try await apply(plan: plan, clearHosts: plan.desiredState.domains.isEmpty)
    }

    func clearAll() async throws -> DomainBlockHelperApplyResult {
        let plan = compiler.compile(desiredState: try DomainBlockDesiredState(domains: [], generatedAt: Date()))
        return try await apply(plan: plan, clearHosts: true)
    }

    func repair(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult {
        let plan = compiler.compile(desiredState: desiredState)
        return try await apply(plan: plan, clearHosts: plan.desiredState.domains.isEmpty)
    }

    func uninstall(withConsent consent: DomainBlockUserConsent) async throws {
        guard consent.approved else { throw DomainBlockHelperError.authorizationDenied }
        _ = try await clearAll()
        try await uninstallLaunchDaemon()
        lastStatus = DomainBlockHelperStatus(
            installState: .notInstalled,
            helperVersion: nil,
            appVersion: Self.currentAppVersion,
            activeDomains: [],
            lastAppliedAt: Date(),
            lastErrorDescription: nil
        )
    }

    private func apply(plan: DomainBlockCompiledRules, clearHosts: Bool) async throws -> DomainBlockHelperApplyResult {
        let currentStatus = loadStatus()
        guard currentStatus.installState == .installed else {
            if currentStatus.installState == .needsUpgrade {
                throw DomainBlockHelperError.versionMismatch(app: currentStatus.appVersion, helper: currentStatus.helperVersion)
            }
            throw DomainBlockHelperError.helperUnavailable("Install the one-time domain blocking helper before applying website blocks.")
        }

        do {
            try ensureStateDirectoryExists()
            let existingHosts = try readDataIfFileExists(at: paths.hostsURL)
            let changedHosts = try DomainBlockHostsReconciler.ownedHostsBlockNeedsUpdate(
                existingData: existingHosts,
                desiredEntries: plan.hostEntries,
                clearing: clearHosts || plan.desiredState.domains.isEmpty
            )

            let oldPF = try readDataIfFileExists(at: paths.pfAnchorURL)
            let shouldManagePF = !plan.desiredState.domains.isEmpty || oldPF != nil
            let pfData = Data(plan.pfAnchorRules.utf8)
            let changedPF = shouldManagePF && (oldPF ?? Data()) != pfData

            if changedHosts || changedPF {
                let requestID = UUID().uuidString
                try stageRequest(
                    requestID: requestID,
                    plan: plan,
                    clearHosts: clearHosts || plan.desiredState.domains.isEmpty,
                    managePF: shouldManagePF
                )
                let daemonStatus = try await waitForStatus(requestID: requestID)
                lastStatus = DomainBlockHelperStatus(
                    installState: .installed,
                    helperVersion: daemonStatus.helperVersion ?? configuration.helperVersion,
                    appVersion: daemonStatus.appVersion ?? Self.currentAppVersion,
                    activeDomains: daemonStatus.activeDomains,
                    lastAppliedAt: daemonStatus.generatedAt ?? plan.desiredState.generatedAt,
                    lastErrorDescription: daemonStatus.lastErrorDescription
                )
            } else {
                lastStatus = DomainBlockHelperStatus(
                    installState: .installed,
                    helperVersion: currentStatus.helperVersion ?? configuration.helperVersion,
                    appVersion: currentStatus.appVersion ?? Self.currentAppVersion,
                    activeDomains: plan.desiredState.domains,
                    lastAppliedAt: plan.desiredState.generatedAt,
                    lastErrorDescription: nil
                )
            }

            return DomainBlockHelperApplyResult(
                status: lastStatus,
                changedHosts: changedHosts,
                changedPFAnchor: changedPF,
                commandOutput: changedHosts || changedPF ? ["LaunchDaemon request applied."] : []
            )
        } catch let error as DomainBlockHelperError {
            lastStatus.lastErrorDescription = error.localizedDescription
            throw error
        } catch {
            lastStatus.lastErrorDescription = error.localizedDescription
            throw error
        }
    }

    private func loadStatus() -> DomainBlockHelperStatus {
        let installedVersion = installedHelperVersion()
        let plistInstalled = FileManager.default.fileExists(atPath: configuration.launchDaemonPlistURL.path)
        let scriptInstalled = FileManager.default.fileExists(atPath: configuration.helperScriptURL.path)
        let installState: DomainBlockHelperInstallState
        if plistInstalled, scriptInstalled {
            installState = installedVersion == configuration.helperVersion ? .installed : .needsUpgrade
        } else {
            installState = .notInstalled
        }

        let daemonStatus = readDaemonStatus()
        return DomainBlockHelperStatus(
            installState: installState,
            helperVersion: installedVersion ?? daemonStatus?.helperVersion,
            appVersion: daemonStatus?.appVersion ?? Self.currentAppVersion,
            activeDomains: daemonStatus?.activeDomains ?? [],
            lastAppliedAt: daemonStatus?.generatedAt,
            lastErrorDescription: daemonStatus?.lastErrorDescription
        )
    }

    private func readDataIfFileExists(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DomainBlockHelperError.fileReadFailed(url.path)
        }
    }

    private func ensureStateDirectoryExists() throws {
        try FileManager.default.createDirectory(at: configuration.stateDirectoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configuration.triggerURL.path) {
            try "ready\n".write(to: configuration.triggerURL, atomically: true, encoding: .utf8)
        }
    }

    private func stageRequest(
        requestID: String,
        plan: DomainBlockCompiledRules,
        clearHosts: Bool,
        managePF: Bool
    ) throws {
        try ensureStateDirectoryExists()
        try writeString(requestID + "\n", to: configuration.stateDirectoryURL.appendingPathComponent("request-id"))
        try writeString((clearHosts ? "true" : "false") + "\n", to: configuration.stateDirectoryURL.appendingPathComponent("clear-hosts"))
        try writeString((managePF ? "true" : "false") + "\n", to: configuration.stateDirectoryURL.appendingPathComponent("manage-pf"))
        try writeString(Self.isoFormatter.string(from: plan.desiredState.generatedAt) + "\n", to: configuration.stateDirectoryURL.appendingPathComponent("generated-at"))
        try writeString((Self.currentAppVersion ?? "unknown") + "\n", to: configuration.stateDirectoryURL.appendingPathComponent("app-version"))
        try writeString(plan.desiredState.domains.joined(separator: "\n") + "\n", to: configuration.activeDomainsURL)
        try writeString(plan.hostsBlock, to: configuration.stateDirectoryURL.appendingPathComponent("hosts-block"))
        try writeString(plan.pfAnchorRules, to: configuration.stateDirectoryURL.appendingPathComponent("pf-anchor"))
        try writeString("\(requestID)\n", to: configuration.triggerURL)
    }

    private func waitForStatus(requestID: String, timeout: TimeInterval = 10) async throws -> DomainBlockLaunchDaemonStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = readDaemonStatus(), status.requestID == requestID {
                if status.result == "error" {
                    throw DomainBlockHelperError.helperUnavailable(status.lastErrorDescription ?? "The helper failed to apply the request.")
                }
                return status
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw DomainBlockHelperError.helperUnavailable("Timed out waiting for the domain blocking helper to apply the request.")
    }

    private func readDaemonStatus() -> DomainBlockLaunchDaemonStatus? {
        guard let contents = try? String(contentsOf: configuration.statusURL, encoding: .utf8) else { return nil }
        var fields: [String: String] = [:]
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            fields[key] = value
        }
        let generatedAt = fields["generatedAt"].flatMap { Self.isoFormatter.date(from: $0) }
        let domains = fields["activeDomains"]?
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        return DomainBlockLaunchDaemonStatus(
            requestID: fields["requestID"],
            result: fields["result"],
            helperVersion: fields["helperVersion"],
            appVersion: fields["appVersion"],
            activeDomains: domains,
            generatedAt: generatedAt,
            changedHosts: fields["changedHosts"] == "true",
            changedPFAnchor: fields["changedPFAnchor"] == "true",
            lastErrorDescription: fields["lastErrorDescription"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private func installLaunchDaemon() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("time-md-domain-helper-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let tempHelper = tempDirectory.appendingPathComponent(configuration.label)
        let tempPlist = tempDirectory.appendingPathComponent("\(configuration.label).plist")
        try helperScript().write(to: tempHelper, atomically: true, encoding: .utf8)
        try launchDaemonPlist().write(to: tempPlist, atomically: true, encoding: .utf8)

        let uid = getuid()
        let gid = getgid()
        let script = [
            "set -e",
            "/bin/mkdir -p \(shellQuote(configuration.helperScriptURL.deletingLastPathComponent().path))",
            "/bin/mkdir -p \(shellQuote(configuration.launchDaemonPlistURL.deletingLastPathComponent().path))",
            "/bin/mkdir -p \(shellQuote(configuration.stateDirectoryURL.path))",
            "/bin/cp \(shellQuote(tempHelper.path)) \(shellQuote(configuration.helperScriptURL.path))",
            "/usr/sbin/chown root:wheel \(shellQuote(configuration.helperScriptURL.path))",
            "/bin/chmod 0755 \(shellQuote(configuration.helperScriptURL.path))",
            "/bin/cp \(shellQuote(tempPlist.path)) \(shellQuote(configuration.launchDaemonPlistURL.path))",
            "/usr/sbin/chown root:wheel \(shellQuote(configuration.launchDaemonPlistURL.path))",
            "/bin/chmod 0644 \(shellQuote(configuration.launchDaemonPlistURL.path))",
            "/usr/sbin/chown -R \(uid):\(gid) \(shellQuote(configuration.stateDirectoryURL.path))",
            "/bin/chmod 0700 \(shellQuote(configuration.stateDirectoryURL.path))",
            "/usr/bin/touch \(shellQuote(configuration.triggerURL.path))",
            "/usr/sbin/chown \(uid):\(gid) \(shellQuote(configuration.triggerURL.path))",
            "/bin/chmod 0600 \(shellQuote(configuration.triggerURL.path))",
            "/bin/launchctl bootout system/\(shellQuote(configuration.label)) >/dev/null 2>&1 || true",
            "/bin/launchctl bootstrap system \(shellQuote(configuration.launchDaemonPlistURL.path))",
            "/bin/launchctl enable system/\(shellQuote(configuration.label))",
            "/bin/launchctl kickstart -k system/\(shellQuote(configuration.label)) >/dev/null 2>&1 || true"
        ].joined(separator: "; ")

        _ = try await runAdministratorScript(script)
    }

    private func uninstallLaunchDaemon() async throws {
        let script = [
            "set -e",
            "/bin/launchctl bootout system/\(shellQuote(configuration.label)) >/dev/null 2>&1 || true",
            "/bin/rm -f \(shellQuote(configuration.launchDaemonPlistURL.path))",
            "/bin/rm -f \(shellQuote(configuration.helperScriptURL.path))"
        ].joined(separator: "; ")
        _ = try await runAdministratorScript(script)
    }

    private func runAdministratorScript(_ script: String) async throws -> String {
        let escapedScript = appleScriptEscaped(script)
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"\(escapedScript)\" with administrator privileges"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw DomainBlockHelperError.commandFailed(
                    command: "osascript do shell script with administrator privileges",
                    exitCode: process.terminationStatus,
                    output: output
                )
            }
            return output
        }.value
    }

    private func installedHelperVersion() -> String? {
        guard let contents = try? String(contentsOf: configuration.helperScriptURL, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") where line.hasPrefix("HELPER_VERSION=") {
            return line
                .replacingOccurrences(of: "HELPER_VERSION=", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }

    private func launchDaemonPlist() -> String {
        """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
        <plist version=\"1.0\">
        <dict>
            <key>Label</key>
            <string>\(xmlEscaped(configuration.label))</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>\(xmlEscaped(configuration.helperScriptURL.path))</string>
                <string>\(xmlEscaped(configuration.stateDirectoryURL.path))</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>WatchPaths</key>
            <array>
                <string>\(xmlEscaped(configuration.triggerURL.path))</string>
            </array>
            <key>StandardOutPath</key>
            <string>\(xmlEscaped(configuration.helperLogURL.path))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscaped(configuration.helperErrorLogURL.path))</string>
        </dict>
        </plist>
        """
    }

    private func helperScript() -> String {
        #"""
        #!/bin/sh
        set -eu

        HELPER_VERSION="\#(configuration.helperVersion)"
        LABEL="\#(configuration.label)"
        BEGIN_MARKER="# >>> time.md domain blocks >>>"
        END_MARKER="# <<< time.md domain blocks <<<"
        HOSTS_PATH="\#(paths.hostsURL.path)"
        PF_ANCHOR_PATH="\#(paths.pfAnchorURL.path)"
        STATE_DIR="${1:-}"

        [ -n "$STATE_DIR" ] || exit 0
        [ -d "$STATE_DIR" ] || exit 0

        REQUEST_ID_FILE="$STATE_DIR/request-id"
        CLEAR_HOSTS_FILE="$STATE_DIR/clear-hosts"
        MANAGE_PF_FILE="$STATE_DIR/manage-pf"
        GENERATED_AT_FILE="$STATE_DIR/generated-at"
        APP_VERSION_FILE="$STATE_DIR/app-version"
        ACTIVE_DOMAINS_FILE="$STATE_DIR/active-domains"
        HOSTS_BLOCK_FILE="$STATE_DIR/hosts-block"
        PF_ANCHOR_FILE="$STATE_DIR/pf-anchor"
        STATUS_FILE="$STATE_DIR/status.env"

        [ -f "$REQUEST_ID_FILE" ] || exit 0

        REQUEST_ID="$(/usr/bin/head -n 1 "$REQUEST_ID_FILE" | /usr/bin/tr -cd 'A-Za-z0-9-')"
        [ -n "$REQUEST_ID" ] || exit 0
        CLEAR_HOSTS="$(/bin/cat "$CLEAR_HOSTS_FILE" 2>/dev/null || /bin/echo false)"
        MANAGE_PF="$(/bin/cat "$MANAGE_PF_FILE" 2>/dev/null || /bin/echo false)"
        GENERATED_AT="$(/bin/cat "$GENERATED_AT_FILE" 2>/dev/null || /bin/echo unknown)"
        APP_VERSION="$(/bin/cat "$APP_VERSION_FILE" 2>/dev/null || /bin/echo unknown)"
        ACTIVE_DOMAINS=""
        if [ -f "$ACTIVE_DOMAINS_FILE" ]; then
          ACTIVE_DOMAINS="$(/usr/bin/tr '\n' ',' < "$ACTIVE_DOMAINS_FILE" | /usr/bin/sed 's/,$//')"
        fi
        CHANGED_HOSTS=false
        CHANGED_PF=false

        write_status() {
          result="$1"
          error_message="$2"
          tmp="$STATUS_FILE.tmp.$$"
          /bin/cat > "$tmp" <<STATUS
        requestID=$REQUEST_ID
        result=$result
        helperVersion=$HELPER_VERSION
        appVersion=$APP_VERSION
        generatedAt=$GENERATED_AT
        activeDomains=$ACTIVE_DOMAINS
        changedHosts=$CHANGED_HOSTS
        changedPFAnchor=$CHANGED_PF
        lastErrorDescription=$error_message
        STATUS
          /bin/chmod 0644 "$tmp" 2>/dev/null || true
          /bin/mv "$tmp" "$STATUS_FILE"
        }

        fail() {
          write_status error "$1"
          exit 1
        }

        validate_hosts_block() {
          [ -f "$HOSTS_BLOCK_FILE" ] || fail "Missing staged hosts block."
          /usr/bin/awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
            $0 == begin { in_block = 1; begin_count++; next }
            $0 == end { in_block = 0; end_count++; next }
            in_block {
              if ($0 ~ /^# Managed by time[.]md/ || $0 ~ /^# Generated at / || $0 ~ /^(0[.]0[.]0[.]0|::1)[[:space:]]+[A-Za-z0-9.-]+$/) next
              ok = 1
            }
            END { if (begin_count != 1 || end_count != 1 || in_block || ok == 1) exit 1 }
          ' "$HOSTS_BLOCK_FILE" || fail "Staged hosts block failed validation."
        }

        validate_pf_anchor() {
          [ -f "$PF_ANCHOR_FILE" ] || fail "Missing staged pf anchor."
          /usr/bin/awk '
            /^$/ { next }
            /^#/ { next }
            /^table <timemd_blocked_hosts> persist [{] [0-9A-Fa-f:., ]+ [}]$/ { next }
            /^block drop quick proto [{] tcp udp [}] from any to <timemd_blocked_hosts>$/ { next }
            /^block drop quick proto [{] tcp udp [}] from <timemd_blocked_hosts> to any$/ { next }
            { bad = 1 }
            END { exit bad == 1 ? 1 : 0 }
          ' "$PF_ANCHOR_FILE" || fail "Staged pf anchor failed validation."
        }

        apply_hosts() {
          tmp_hosts="$(/usr/bin/mktemp /tmp/time-md-hosts.XXXXXX)"
          if [ -f "$HOSTS_PATH" ]; then
            /usr/bin/awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
              $0 == begin { skip = 1; next }
              $0 == end { skip = 0; next }
              skip { next }
              { print }
            ' "$HOSTS_PATH" > "$tmp_hosts"
          else
            : > "$tmp_hosts"
          fi

          if [ "$CLEAR_HOSTS" != "true" ]; then
            validate_hosts_block
            /bin/echo "" >> "$tmp_hosts"
            /bin/cat "$HOSTS_BLOCK_FILE" >> "$tmp_hosts"
          fi

          if [ ! -f "$HOSTS_PATH" ] || ! /usr/bin/cmp -s "$tmp_hosts" "$HOSTS_PATH"; then
            /bin/cp "$tmp_hosts" "$HOSTS_PATH" || fail "Unable to write hosts file."
            /bin/chmod 0644 "$HOSTS_PATH" || true
            CHANGED_HOSTS=true
          fi
          /bin/rm -f "$tmp_hosts"
        }

        apply_pf() {
          [ "$MANAGE_PF" = "true" ] || return 0
          validate_pf_anchor
          /bin/mkdir -p "$(/usr/bin/dirname "$PF_ANCHOR_PATH")" || fail "Unable to create pf anchor directory."
          if [ ! -f "$PF_ANCHOR_PATH" ] || ! /usr/bin/cmp -s "$PF_ANCHOR_FILE" "$PF_ANCHOR_PATH"; then
            /bin/cp "$PF_ANCHOR_FILE" "$PF_ANCHOR_PATH" || fail "Unable to write pf anchor."
            /bin/chmod 0644 "$PF_ANCHOR_PATH" || true
            CHANGED_PF=true
          fi
          if [ "$CHANGED_PF" = "true" ]; then
            pf_output="$(/sbin/pfctl -a "$LABEL" -f "$PF_ANCHOR_PATH" 2>&1)" || fail "pfctl failed: $pf_output"
          fi
        }

        apply_hosts
        apply_pf

        if [ "$CHANGED_HOSTS" = "true" ]; then
          /usr/bin/dscacheutil -flushcache 2>/dev/null || true
          /usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true
        fi

        write_status ok ""
        exit 0
        """#
    }

    private func writeString(_ value: String, to url: URL) throws {
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static var currentAppVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}


/// File-system implementation intended to run inside a privileged helper or a
/// developer-only elevated process. It is path-injectable so tests never touch
/// `/etc/hosts` or the system pf configuration.
actor LocalDomainBlockHelperClient: DomainBlockHelperClient {
    private let paths: DomainBlockSystemPaths
    private let compiler: DomainBlockRuleCompiler
    private let commandRunner: (any DomainBlockCommandRunning)?
    private var lastStatus: DomainBlockHelperStatus

    nonisolated init(
        paths: DomainBlockSystemPaths = DomainBlockSystemPaths(),
        compiler: DomainBlockRuleCompiler = DomainBlockRuleCompiler(),
        commandRunner: (any DomainBlockCommandRunning)? = ProcessDomainBlockCommandRunner()
    ) {
        self.paths = paths
        self.compiler = compiler
        self.commandRunner = commandRunner
        self.lastStatus = DomainBlockHelperStatus(
            installState: .installed,
            helperVersion: nil,
            appVersion: nil,
            activeDomains: [],
            lastAppliedAt: nil,
            lastErrorDescription: nil
        )
    }

    func status() async -> DomainBlockHelperStatus { lastStatus }

    func installOrUpgrade(withConsent consent: DomainBlockUserConsent) async throws -> DomainBlockHelperStatus {
        guard consent.approved else { throw DomainBlockHelperError.authorizationDenied }
        lastStatus.installState = .installed
        return lastStatus
    }

    func apply(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult {
        let plan = compiler.compile(desiredState: desiredState)
        return try await apply(plan: plan, clearHosts: false)
    }

    func clearAll() async throws -> DomainBlockHelperApplyResult {
        let plan = compiler.compile(desiredState: try DomainBlockDesiredState(domains: [], generatedAt: Date()))
        return try await apply(plan: plan, clearHosts: true)
    }

    func repair(_ desiredState: DomainBlockDesiredState) async throws -> DomainBlockHelperApplyResult {
        try await apply(desiredState)
    }

    func uninstall(withConsent consent: DomainBlockUserConsent) async throws {
        guard consent.approved else { throw DomainBlockHelperError.authorizationDenied }
        _ = try await clearAll()
        lastStatus.installState = .notInstalled
    }

    private func apply(plan: DomainBlockCompiledRules, clearHosts: Bool) async throws -> DomainBlockHelperApplyResult {
        do {
            let existingHosts = try readDataIfFileExists(at: paths.hostsURL)
            let newHosts = clearHosts || plan.desiredState.domains.isEmpty
                ? try DomainBlockHostsReconciler.clearingOwnedBlock(from: existingHosts)
                : try DomainBlockHostsReconciler.applyingOwnedBlock(plan.hostsBlock, to: existingHosts)
            let changedHosts = try DomainBlockHostsReconciler.ownedHostsBlockNeedsUpdate(
                existingData: existingHosts,
                desiredEntries: plan.hostEntries,
                clearing: clearHosts || plan.desiredState.domains.isEmpty
            )
            if changedHosts { try atomicWrite(newHosts, to: paths.hostsURL) }

            let oldPF = try readDataIfFileExists(at: paths.pfAnchorURL)
            let shouldManagePF = !plan.desiredState.domains.isEmpty || oldPF != nil
            let pfData = Data(plan.pfAnchorRules.utf8)
            let changedPF = shouldManagePF && (oldPF ?? Data()) != pfData
            if changedPF { try atomicWrite(pfData, to: paths.pfAnchorURL) }

            var outputs: [String] = []
            if changedPF, let commandRunner {
                outputs.append(try await commandRunner.run("/sbin/pfctl", arguments: ["-a", DomainBlockRuleCompiler.pfAnchorName, "-f", paths.pfAnchorURL.path]))
            }
            if changedHosts, let commandRunner {
                outputs.append(try await commandRunner.run("/usr/bin/dscacheutil", arguments: ["-flushcache"]))
                outputs.append(try await commandRunner.run("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"]))
            }

            lastStatus = DomainBlockHelperStatus(
                installState: .installed,
                helperVersion: lastStatus.helperVersion,
                appVersion: lastStatus.appVersion,
                activeDomains: plan.desiredState.domains,
                lastAppliedAt: plan.desiredState.generatedAt,
                lastErrorDescription: nil
            )
            return DomainBlockHelperApplyResult(status: lastStatus, changedHosts: changedHosts, changedPFAnchor: changedPF, commandOutput: outputs)
        } catch let error as DomainBlockHelperError {
            lastStatus.lastErrorDescription = error.localizedDescription
            throw error
        } catch {
            let wrapped = DomainBlockHelperError.fileWriteFailed(paths.hostsURL.path)
            lastStatus.lastErrorDescription = error.localizedDescription
            throw wrapped
        }
    }

    private func readDataIfFileExists(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DomainBlockHelperError.fileReadFailed(url.path)
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).time-md.tmp.\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw DomainBlockHelperError.fileWriteFailed(url.path)
        }
    }
}
