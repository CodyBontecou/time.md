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
        let changedHosts = newPlan.hostsBlock != currentPlan?.hostsBlock
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

/// App-side helper that applies the compiled hosts/pf state through macOS'
/// standard administrator prompt. This makes domain-network blocking actually
/// enforceable from the app process while still keeping all writes limited to
/// time.md's owned hosts marker block and pf anchor.
actor PrivilegedDomainBlockHelperClient: DomainBlockHelperClient {
    static let shared = PrivilegedDomainBlockHelperClient()

    private let paths: DomainBlockSystemPaths
    private let compiler: DomainBlockRuleCompiler
    private var lastStatus: DomainBlockHelperStatus

    nonisolated init(
        paths: DomainBlockSystemPaths = DomainBlockSystemPaths(),
        compiler: DomainBlockRuleCompiler = DomainBlockRuleCompiler()
    ) {
        self.paths = paths
        self.compiler = compiler
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
            let oldHosts = existingHosts ?? Data()
            let changedHosts = oldHosts != newHosts

            let pfData = Data(plan.pfAnchorRules.utf8)
            let oldPF = try readDataIfFileExists(at: paths.pfAnchorURL) ?? Data()
            let changedPF = oldPF != pfData

            var outputs: [String] = []
            if changedHosts || changedPF {
                outputs.append(try await applyWithAdministratorPrivileges(hostsData: newHosts, pfData: pfData))
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
            lastStatus.lastErrorDescription = error.localizedDescription
            throw error
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

    private func applyWithAdministratorPrivileges(hostsData: Data, pfData: Data) async throws -> String {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("time-md-domain-blocks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let tempHosts = tempDirectory.appendingPathComponent("hosts")
        let tempPF = tempDirectory.appendingPathComponent("pf-anchor")
        try hostsData.write(to: tempHosts, options: .atomic)
        try pfData.write(to: tempPF, options: .atomic)

        let script = [
            "set -e",
            "/bin/mkdir -p \(shellQuote(paths.pfAnchorURL.deletingLastPathComponent().path))",
            "/bin/cp \(shellQuote(tempHosts.path)) \(shellQuote(paths.hostsURL.path))",
            "/bin/chmod 0644 \(shellQuote(paths.hostsURL.path))",
            "/bin/cp \(shellQuote(tempPF.path)) \(shellQuote(paths.pfAnchorURL.path))",
            "/bin/chmod 0644 \(shellQuote(paths.pfAnchorURL.path))",
            "/sbin/pfctl -a \(shellQuote(DomainBlockRuleCompiler.pfAnchorName)) -f \(shellQuote(paths.pfAnchorURL.path))",
            "/usr/bin/dscacheutil -flushcache",
            "/usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true"
        ].joined(separator: "; ")

        return try await runAdministratorScript(script)
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

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
            let oldHosts = existingHosts ?? Data()
            let changedHosts = oldHosts != newHosts
            if changedHosts { try atomicWrite(newHosts, to: paths.hostsURL) }

            let pfData = Data(plan.pfAnchorRules.utf8)
            let oldPF = try readDataIfFileExists(at: paths.pfAnchorURL) ?? Data()
            let changedPF = oldPF != pfData
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
