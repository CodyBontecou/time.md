import Foundation

/// Bridges pure policy state to a domain blocking helper. The policy engine
/// remains unaware of root-only system details; this coordinator only publishes
/// the full active domain set that should currently be enforced.
struct DomainBlockEnforcer: Sendable {
    var engine: BlockPolicyEngine
    var helper: any DomainBlockHelperClient
    var compilerClock: @Sendable () -> Date
    var additionalHostnameProvider: @Sendable ([ActiveBlock]) -> [String]

    nonisolated init(
        engine: BlockPolicyEngine = BlockPolicyEngine(),
        helper: any DomainBlockHelperClient,
        compilerClock: @escaping @Sendable () -> Date = { Date() },
        additionalHostnameProvider: @escaping @Sendable ([ActiveBlock]) -> [String] = { DomainBlockEnforcer.recentlyObservedSubdomainHostnames(for: $0) }
    ) {
        self.engine = engine
        self.helper = helper
        self.compilerClock = compilerClock
        self.additionalHostnameProvider = additionalHostnameProvider
    }

    @discardableResult
    func reconcileActiveDomainBlocks(now: Date = Date()) async throws -> DomainBlockHelperApplyResult {
        _ = try engine.clearExpiredBlocks(now: now)
        let activeBlocks = try engine.activeBlocks(now: now)
        let desiredState = try DomainBlockDesiredState(
            activeBlocks: activeBlocks,
            generatedAt: compilerClock(),
            additionalHostnames: additionalHostnameProvider(activeBlocks)
        )
        return try await helper.apply(desiredState)
    }

    @discardableResult
    func clearAllDomainBlocks() async throws -> DomainBlockHelperApplyResult {
        try await helper.clearAll()
    }

    @discardableResult
    func repairActiveDomainBlocks(now: Date = Date()) async throws -> DomainBlockHelperApplyResult {
        let activeBlocks = try engine.activeBlocks(now: now)
        let desiredState = try DomainBlockDesiredState(
            activeBlocks: activeBlocks,
            generatedAt: compilerClock(),
            additionalHostnames: additionalHostnameProvider(activeBlocks)
        )
        return try await helper.repair(desiredState)
    }

    nonisolated static func recentlyObservedSubdomainHostnames(for activeBlocks: [ActiveBlock]) -> [String] {
        let activeDomains: [String] = activeBlocks.compactMap { block in
            guard block.state.target.type == .domain else { return nil }
            if let rule = block.rule, (!rule.enabled || rule.enforcementMode != .domainNetwork) { return nil }
            return block.state.target.value
        }
        guard !activeDomains.isEmpty else { return [] }

        let events: [BlockAuditEvent]
        do {
            events = try BlockRuleStore.fetchAuditEvents(limit: 1_000)
        } catch {
            return []
        }

        var seen = Set<String>()
        var hostnames: [String] = []
        for event in events where event.kind == .accessObserved {
            guard let target = event.target, target.type == .domain else { continue }
            for domain in activeDomains where isStrictSubdomain(target.value, of: domain) {
                guard seen.insert(target.value).inserted else { continue }
                hostnames.append(target.value)
            }
        }
        return hostnames.sorted()
    }

    nonisolated private static func isStrictSubdomain(_ hostname: String, of domain: String) -> Bool {
        hostname != domain && hostname.hasSuffix(".\(domain)")
    }
}
