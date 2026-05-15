import Foundation

/// Coarse safety state for the blocking subsystem.
enum BlockingDiagnosticSeverity: String, Codable, Comparable, Sendable {
    case healthy
    case degraded
    case broken

    static func < (lhs: BlockingDiagnosticSeverity, rhs: BlockingDiagnosticSeverity) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ severity: BlockingDiagnosticSeverity) -> Int {
        switch severity {
        case .healthy: return 0
        case .degraded: return 1
        case .broken: return 2
        }
    }
}

struct BlockingDiagnosticCheck: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var severity: BlockingDiagnosticSeverity
    var message: String
    var recoveryHint: String?
}

struct BlockingDiagnosticsReport: Codable, Hashable, Sendable {
    var generatedAt: Date
    var overallSeverity: BlockingDiagnosticSeverity
    var activeBlockCount: Int
    var activeDomainCount: Int
    var checks: [BlockingDiagnosticCheck]

    var needsUserAttention: Bool {
        overallSeverity == .degraded || overallSeverity == .broken
    }
}

struct BlockingManagedFileSnapshot: Codable, Hashable, Sendable {
    enum OwnedBlockState: String, Codable, Sendable {
        case missing
        case complete
        case partial
        case unreadable
    }

    var path: String
    var exists: Bool
    var ownedBlockState: OwnedBlockState
    var errorDescription: String?
}

struct BlockingManagedFilesSnapshot: Codable, Hashable, Sendable {
    var hosts: BlockingManagedFileSnapshot
    var pfAnchor: BlockingManagedFileSnapshot
}

protocol BlockingManagedFileInspecting: Sendable {
    func snapshot() -> BlockingManagedFilesSnapshot
}

struct DomainBlockingManagedFileInspector: BlockingManagedFileInspecting {
    var paths: DomainBlockSystemPaths

    nonisolated init(paths: DomainBlockSystemPaths = DomainBlockSystemPaths()) {
        self.paths = paths
    }

    func snapshot() -> BlockingManagedFilesSnapshot {
        BlockingManagedFilesSnapshot(
            hosts: inspectHosts(at: paths.hostsURL),
            pfAnchor: inspectPFAnchor(at: paths.pfAnchorURL)
        )
    }

    private func inspectHosts(at url: URL) -> BlockingManagedFileSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BlockingManagedFileSnapshot(path: url.path, exists: false, ownedBlockState: .missing, errorDescription: nil)
        }

        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                return BlockingManagedFileSnapshot(path: url.path, exists: true, ownedBlockState: .unreadable, errorDescription: DomainBlockHelperError.hostsFileNotUTF8.localizedDescription)
            }
            let beginCount = text.components(separatedBy: DomainBlockRuleCompiler.hostsBeginMarker).count - 1
            let endCount = text.components(separatedBy: DomainBlockRuleCompiler.hostsEndMarker).count - 1
            if beginCount == 0, endCount == 0 {
                return BlockingManagedFileSnapshot(path: url.path, exists: true, ownedBlockState: .missing, errorDescription: nil)
            }
            if beginCount == endCount {
                return BlockingManagedFileSnapshot(path: url.path, exists: true, ownedBlockState: .complete, errorDescription: nil)
            }
            return BlockingManagedFileSnapshot(path: url.path, exists: true, ownedBlockState: .partial, errorDescription: "Found an incomplete time.md hosts marker block.")
        } catch {
            return BlockingManagedFileSnapshot(path: url.path, exists: true, ownedBlockState: .unreadable, errorDescription: error.localizedDescription)
        }
    }

    private func inspectPFAnchor(at url: URL) -> BlockingManagedFileSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BlockingManagedFileSnapshot(path: url.path, exists: false, ownedBlockState: .missing, errorDescription: nil)
        }

        do {
            let data = try Data(contentsOf: url)
            let state: BlockingManagedFileSnapshot.OwnedBlockState = data.isEmpty ? .missing : .complete
            return BlockingManagedFileSnapshot(path: url.path, exists: true, ownedBlockState: state, errorDescription: nil)
        } catch {
            return BlockingManagedFileSnapshot(path: url.path, exists: true, ownedBlockState: .unreadable, errorDescription: error.localizedDescription)
        }
    }
}

protocol BlockingPolicyStateStore: Sendable {
    func fetchRules(includeDisabled: Bool) throws -> [BlockRule]
    func fetchStates() throws -> [BlockState]
    func upsert(state: BlockState) throws
    func appendAuditEvent(_ event: BlockAuditEvent) throws
}

struct LiveBlockingPolicyStateStore: BlockingPolicyStateStore {
    nonisolated init() {}

    func fetchRules(includeDisabled: Bool) throws -> [BlockRule] {
        try BlockRuleStore.fetchRules(includeDisabled: includeDisabled)
    }

    func fetchStates() throws -> [BlockState] {
        try BlockRuleStore.fetchStates()
    }

    func upsert(state: BlockState) throws {
        try BlockRuleStore.upsert(state: state)
    }

    func appendAuditEvent(_ event: BlockAuditEvent) throws {
        try BlockRuleStore.appendAuditEvent(event)
    }
}

struct BlockingDiagnosticsService: Sendable {
    var store: any BlockingPolicyStateStore
    var engine: BlockPolicyEngine
    var helper: any DomainBlockHelperClient
    var fileInspector: any BlockingManagedFileInspecting
    var appEnforcerEnabledProvider: @Sendable () -> Bool
    var now: @Sendable () -> Date

    init(
        store: any BlockingPolicyStateStore = LiveBlockingPolicyStateStore(),
        engine: BlockPolicyEngine = BlockPolicyEngine(),
        helper: any DomainBlockHelperClient = PrivilegedDomainBlockHelperClient.shared,
        fileInspector: any BlockingManagedFileInspecting = DomainBlockingManagedFileInspector(),
        appEnforcerEnabledProvider: @escaping @Sendable () -> Bool = { AppBlockEnforcer.isLiveEnabled },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.engine = engine
        self.helper = helper
        self.fileInspector = fileInspector
        self.appEnforcerEnabledProvider = appEnforcerEnabledProvider
        self.now = now
    }

    func report() async -> BlockingDiagnosticsReport {
        let generatedAt = now()
        var checks: [BlockingDiagnosticCheck] = []
        var activeBlocks: [ActiveBlock] = []
        var activeDomainDesired: [String] = []

        do {
            let rules = try store.fetchRules(includeDisabled: true)
            let states = try store.fetchStates()
            checks.append(BlockingDiagnosticCheck(
                id: "policy-store",
                title: "Policy store",
                severity: .healthy,
                message: "Rules and cooldown state can be read.",
                recoveryHint: nil
            ))
            activeBlocks = (try? engine.activeBlocks(rules: rules, states: states, now: generatedAt)) ?? []
            activeDomainDesired = (try? DomainBlockDesiredState(activeBlocks: activeBlocks, generatedAt: generatedAt).domains) ?? []
        } catch {
            checks.append(BlockingDiagnosticCheck(
                id: "policy-store",
                title: "Policy store",
                severity: .broken,
                message: "Blocking rules or state could not be read: \(error.localizedDescription)",
                recoveryHint: "Use repair to rebuild the local blocking database, or remove the blocking-rules.db file after exporting diagnostics."
            ))
        }

        do {
            let expiredCount = try store.fetchStates().filter { state in
                guard let blockedUntil = state.blockedUntil else { return false }
                return blockedUntil <= generatedAt
            }.count
            checks.append(BlockingDiagnosticCheck(
                id: "expired-state",
                title: "Expired cooldown cleanup",
                severity: expiredCount == 0 ? .healthy : .degraded,
                message: expiredCount == 0 ? "No stale expired cooldowns are persisted." : "\(expiredCount) expired cooldown(s) should be cleared.",
                recoveryHint: expiredCount == 0 ? nil : "Run Clear expired or Repair blocking state."
            ))
        } catch {
            // Store check above already records the broken state.
        }

        let helperStatus = await helper.status()
        checks.append(helperCheck(status: helperStatus, desiredDomains: activeDomainDesired))
        checks.append(helperDomainMismatchCheck(status: helperStatus, desiredDomains: activeDomainDesired))

        let files = fileInspector.snapshot()
        checks.append(hostsCheck(snapshot: files.hosts, desiredDomains: activeDomainDesired))
        checks.append(pfAnchorCheck(snapshot: files.pfAnchor, desiredDomains: activeDomainDesired))

        let activeAppBlocks = activeBlocks.filter { block in
            guard let rule = block.rule else { return block.state.target.type != .domain }
            return (block.state.target.type == .app || block.state.target.type == .category) && rule.enforcementMode != .monitorOnly
        }
        let appEnforcerEnabled = appEnforcerEnabledProvider()
        checks.append(BlockingDiagnosticCheck(
            id: "app-enforcer",
            title: "App/category enforcer",
            severity: activeAppBlocks.isEmpty || appEnforcerEnabled ? .healthy : .degraded,
            message: appEnforcerEnabled ? "App/category enforcement watcher is enabled." : "App/category enforcement watcher is disabled while app/category blocks may be active.",
            recoveryHint: appEnforcerEnabled ? nil : "Enable app/category enforcement or remove active app/category blocks."
        ))

        let overall = checks.map(\.severity).max() ?? .healthy

        return BlockingDiagnosticsReport(
            generatedAt: generatedAt,
            overallSeverity: overall,
            activeBlockCount: activeBlocks.count,
            activeDomainCount: activeDomainDesired.count,
            checks: checks
        )
    }

    private func helperCheck(status: DomainBlockHelperStatus, desiredDomains: [String]) -> BlockingDiagnosticCheck {
        if let error = status.lastErrorDescription, !error.isEmpty {
            return BlockingDiagnosticCheck(
                id: "helper-status",
                title: "Domain helper connectivity",
                severity: .broken,
                message: "Helper reported an error: \(error)",
                recoveryHint: "Run Repair helper or Remove all managed blocks."
            )
        }

        switch status.installState {
        case .installed:
            return BlockingDiagnosticCheck(id: "helper-status", title: "Domain helper connectivity", severity: .healthy, message: "Domain helper is reachable.", recoveryHint: nil)
        case .needsUpgrade:
            return BlockingDiagnosticCheck(id: "helper-status", title: "Domain helper connectivity", severity: .degraded, message: "Domain helper needs an upgrade before enforcing blocks.", recoveryHint: "Install or upgrade the helper.")
        case .notInstalled, .unavailable:
            let severity: BlockingDiagnosticSeverity = desiredDomains.isEmpty ? .healthy : .degraded
            return BlockingDiagnosticCheck(id: "helper-status", title: "Domain helper connectivity", severity: severity, message: desiredDomains.isEmpty ? "No active domain blocks require the helper." : "Active domain blocks exist but the helper is not installed or unavailable.", recoveryHint: desiredDomains.isEmpty ? nil : "Install the helper or remove active domain blocks.")
        }
    }

    private func helperDomainMismatchCheck(status: DomainBlockHelperStatus, desiredDomains: [String]) -> BlockingDiagnosticCheck {
        let actual = status.activeDomains.sorted()
        let desired = desiredDomains.sorted()
        let matches = actual == desired
        return BlockingDiagnosticCheck(
            id: "domain-desired-state",
            title: "Domain desired state",
            severity: matches ? .healthy : .degraded,
            message: matches ? "Helper active domain set matches policy state." : "Helper domains \(actual) do not match desired domains \(desired).",
            recoveryHint: matches ? nil : "Run Repair helper to reconcile the owned hosts block and pf anchor."
        )
    }

    private func hostsCheck(snapshot: BlockingManagedFileSnapshot, desiredDomains: [String]) -> BlockingDiagnosticCheck {
        switch snapshot.ownedBlockState {
        case .partial, .unreadable:
            return BlockingDiagnosticCheck(id: "hosts-owned-block", title: "Owned hosts block", severity: .broken, message: snapshot.errorDescription ?? "The owned hosts block is invalid.", recoveryHint: "Run Remove all managed blocks or Repair helper from an administrator-approved helper.")
        case .complete:
            return BlockingDiagnosticCheck(id: "hosts-owned-block", title: "Owned hosts block", severity: .healthy, message: "The time.md-owned hosts block is complete.", recoveryHint: nil)
        case .missing:
            let severity: BlockingDiagnosticSeverity = desiredDomains.isEmpty ? .healthy : .degraded
            return BlockingDiagnosticCheck(id: "hosts-owned-block", title: "Owned hosts block", severity: severity, message: desiredDomains.isEmpty ? "No owned hosts block is needed." : "Active domain blocks exist but no owned hosts block was found.", recoveryHint: desiredDomains.isEmpty ? nil : "Run Repair helper to write the managed hosts block.")
        }
    }

    private func pfAnchorCheck(snapshot: BlockingManagedFileSnapshot, desiredDomains: [String]) -> BlockingDiagnosticCheck {
        switch snapshot.ownedBlockState {
        case .unreadable:
            return BlockingDiagnosticCheck(id: "pf-anchor", title: "Owned pf anchor", severity: .broken, message: snapshot.errorDescription ?? "The owned pf anchor could not be read.", recoveryHint: "Run Repair helper or Remove all managed blocks.")
        case .complete:
            return BlockingDiagnosticCheck(id: "pf-anchor", title: "Owned pf anchor", severity: .healthy, message: "The time.md-owned pf anchor file exists.", recoveryHint: nil)
        case .missing, .partial:
            let severity: BlockingDiagnosticSeverity = desiredDomains.isEmpty ? .healthy : .degraded
            return BlockingDiagnosticCheck(id: "pf-anchor", title: "Owned pf anchor", severity: severity, message: desiredDomains.isEmpty ? "No pf anchor rules are needed." : "Active domain blocks exist but the owned pf anchor is missing.", recoveryHint: desiredDomains.isEmpty ? nil : "Run Repair helper to rewrite the anchor.")
        }
    }
}
