import Foundation

struct BlockingRecoveryResult: Codable, Hashable, Sendable {
    var clearedExpiredStates: Int
    var clearedActiveStates: Int
    var helperResult: DomainBlockHelperApplyResult?
    var uninstalledHelper: Bool
    var messages: [String]
}

/// User-initiated recovery operations for the blocking subsystem. These are
/// intentionally conservative: removing managed blocks clears active cooldown
/// timestamps and the helper-owned hosts/pf state, but it does not delete user
/// rule definitions or strike history.
struct BlockingRecoveryService: Sendable {
    var store: any BlockingPolicyStateStore
    var engine: BlockPolicyEngine
    var domainEnforcer: DomainBlockEnforcer
    var helper: any DomainBlockHelperClient
    var now: @Sendable () -> Date

    init(
        store: any BlockingPolicyStateStore = LiveBlockingPolicyStateStore(),
        engine: BlockPolicyEngine = BlockPolicyEngine(),
        helper: any DomainBlockHelperClient = PrivilegedDomainBlockHelperClient.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.engine = engine
        self.helper = helper
        self.domainEnforcer = DomainBlockEnforcer(engine: engine, helper: helper, compilerClock: now)
        self.now = now
    }

    @discardableResult
    func clearExpiredBlocks() throws -> BlockingRecoveryResult {
        let cleared = try engine.clearExpiredBlocks(now: now())
        try store.appendAuditEvent(BlockAuditEvent(
            timestamp: now(),
            kind: .stateUpdated,
            message: "Recovery cleared expired blocking cooldowns",
            metadata: ["clearedExpiredStates": String(cleared.count)]
        ))
        return BlockingRecoveryResult(
            clearedExpiredStates: cleared.count,
            clearedActiveStates: 0,
            helperResult: nil,
            uninstalledHelper: false,
            messages: ["Cleared \(cleared.count) expired cooldown(s)."]
        )
    }

    @discardableResult
    func repairManagedDomainBlocks() async throws -> BlockingRecoveryResult {
        let cleared = try engine.clearExpiredBlocks(now: now())
        let helperResult = try await domainEnforcer.repairActiveDomainBlocks(now: now())
        try store.appendAuditEvent(BlockAuditEvent(
            timestamp: now(),
            kind: .stateUpdated,
            message: "Recovery repaired managed domain blocking state",
            metadata: [
                "clearedExpiredStates": String(cleared.count),
                "activeDomains": helperResult.status.activeDomains.joined(separator: ",")
            ]
        ))
        return BlockingRecoveryResult(
            clearedExpiredStates: cleared.count,
            clearedActiveStates: 0,
            helperResult: helperResult,
            uninstalledHelper: false,
            messages: [
                "Cleared \(cleared.count) expired cooldown(s).",
                "Reconciled \(helperResult.status.activeDomains.count) active domain block(s)."
            ]
        )
    }

    @discardableResult
    func removeAllManagedBlocks() async throws -> BlockingRecoveryResult {
        let currentTime = now()
        var clearedActiveStates = 0
        for var state in try store.fetchStates() where state.blockedUntil != nil {
            state.blockedUntil = nil
            state.updatedAt = currentTime
            try store.upsert(state: state)
            clearedActiveStates += 1
        }

        let helperResult = try await domainEnforcer.clearAllDomainBlocks()
        try store.appendAuditEvent(BlockAuditEvent(
            timestamp: currentTime,
            kind: .stateUpdated,
            message: "Recovery removed all time.md-managed active blocks",
            metadata: [
                "clearedActiveStates": String(clearedActiveStates),
                "clearedHelperDomains": String(helperResult.status.activeDomains.count)
            ]
        ))

        return BlockingRecoveryResult(
            clearedExpiredStates: 0,
            clearedActiveStates: clearedActiveStates,
            helperResult: helperResult,
            uninstalledHelper: false,
            messages: [
                "Cleared \(clearedActiveStates) active cooldown(s).",
                "Removed all time.md-owned domain helper rules."
            ]
        )
    }

    @discardableResult
    func uninstallHelper(withConsent consent: DomainBlockUserConsent) async throws -> BlockingRecoveryResult {
        let removal = try await removeAllManagedBlocks()
        try await helper.uninstall(withConsent: consent)
        try store.appendAuditEvent(BlockAuditEvent(
            timestamp: now(),
            kind: .stateUpdated,
            message: "Recovery uninstalled the time.md domain helper",
            metadata: ["approved": String(consent.approved)]
        ))
        return BlockingRecoveryResult(
            clearedExpiredStates: removal.clearedExpiredStates,
            clearedActiveStates: removal.clearedActiveStates,
            helperResult: removal.helperResult,
            uninstalledHelper: true,
            messages: removal.messages + ["Uninstalled the time.md domain helper."]
        )
    }
}
