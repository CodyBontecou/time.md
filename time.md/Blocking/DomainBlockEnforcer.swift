import Foundation

/// Bridges pure policy state to a domain blocking helper. The policy engine
/// remains unaware of root-only system details; this coordinator only publishes
/// the full active domain set that should currently be enforced.
struct DomainBlockEnforcer: Sendable {
    var engine: BlockPolicyEngine
    var helper: any DomainBlockHelperClient
    var compilerClock: @Sendable () -> Date

    nonisolated init(
        engine: BlockPolicyEngine = BlockPolicyEngine(),
        helper: any DomainBlockHelperClient,
        compilerClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.engine = engine
        self.helper = helper
        self.compilerClock = compilerClock
    }

    @discardableResult
    func reconcileActiveDomainBlocks(now: Date = Date()) async throws -> DomainBlockHelperApplyResult {
        _ = try engine.clearExpiredBlocks(now: now)
        let activeBlocks = try engine.activeBlocks(now: now)
        let desiredState = try DomainBlockDesiredState(activeBlocks: activeBlocks, generatedAt: compilerClock())
        return try await helper.apply(desiredState)
    }

    @discardableResult
    func clearAllDomainBlocks() async throws -> DomainBlockHelperApplyResult {
        try await helper.clearAll()
    }

    @discardableResult
    func repairActiveDomainBlocks(now: Date = Date()) async throws -> DomainBlockHelperApplyResult {
        let activeBlocks = try engine.activeBlocks(now: now)
        let desiredState = try DomainBlockDesiredState(activeBlocks: activeBlocks, generatedAt: compilerClock())
        return try await helper.repair(desiredState)
    }
}
