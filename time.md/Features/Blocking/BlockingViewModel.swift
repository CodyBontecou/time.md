import Foundation

protocol BlockingRuleStoring: Sendable {
    func fetchRules(includeDisabled: Bool) throws -> [BlockRule]
    func fetchStates() throws -> [BlockState]
    func upsert(rule: BlockRule) throws
    func deleteRule(id: UUID, deleteState: Bool) throws
    func deleteState(for target: BlockTarget) throws
    func upsert(state: BlockState) throws
}

struct LiveBlockingRuleStore: BlockingRuleStoring {
    nonisolated init() {}

    func fetchRules(includeDisabled: Bool) throws -> [BlockRule] {
        try BlockRuleStore.fetchRules(includeDisabled: includeDisabled)
    }

    func fetchStates() throws -> [BlockState] {
        try BlockRuleStore.fetchStates()
    }

    func upsert(rule: BlockRule) throws {
        try BlockRuleStore.upsert(rule: rule)
    }

    func deleteRule(id: UUID, deleteState: Bool) throws {
        try BlockRuleStore.deleteRule(id: id, deleteState: deleteState)
    }

    func deleteState(for target: BlockTarget) throws {
        try BlockRuleStore.deleteState(for: target)
    }

    func upsert(state: BlockState) throws {
        try BlockRuleStore.upsert(state: state)
    }
}

protocol BlockingHelperStatusProviding: Sendable {
    func status() async -> DomainBlockHelperStatus
}

struct LiveBlockingHelperStatusProvider: BlockingHelperStatusProviding {
    nonisolated init() {}

    func status() async -> DomainBlockHelperStatus {
        await PrivilegedDomainBlockHelperClient.shared.status()
    }
}

struct StaticBlockingHelperStatusProvider: BlockingHelperStatusProviding {
    var value: DomainBlockHelperStatus

    init(_ value: DomainBlockHelperStatus) {
        self.value = value
    }

    func status() async -> DomainBlockHelperStatus {
        value
    }
}

enum BlockingPolicyPreset: String, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1m ×2, max 4h"
    case fiveMinutes = "5m ×2, max 8h"
    case custom = "Custom"

    var id: String { rawValue }

    func policy(
        customBaseSeconds: TimeInterval = 60,
        customMultiplier: Double = 2,
        customMaxSeconds: TimeInterval = 4 * 60 * 60,
        customMinimumSessionSeconds: TimeInterval = 0
    ) throws -> BlockPolicy {
        switch self {
        case .oneMinute:
            return try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 4 * 60 * 60)
        case .fiveMinutes:
            return try BlockPolicy(baseDurationSeconds: 5 * 60, multiplier: 2, maxDurationSeconds: 8 * 60 * 60)
        case .custom:
            return try BlockPolicy(
                baseDurationSeconds: customBaseSeconds,
                multiplier: customMultiplier,
                maxDurationSeconds: customMaxSeconds,
                minimumSessionSeconds: customMinimumSessionSeconds
            )
        }
    }

    static func matching(_ policy: BlockPolicy) -> BlockingPolicyPreset {
        if policy.baseDurationSeconds == 60, policy.multiplier == 2, policy.maxDurationSeconds == 4 * 60 * 60 {
            return .oneMinute
        }
        if policy.baseDurationSeconds == 5 * 60, policy.multiplier == 2, policy.maxDurationSeconds == 8 * 60 * 60 {
            return .fiveMinutes
        }
        return .custom
    }
}

struct BlockingRuleDraft: Equatable, Sendable {
    var editingRuleID: UUID?
    var targetType: BlockTargetType
    var targetValue: String
    var displayName: String
    var enabled: Bool
    var enforcementMode: BlockEnforcementMode
    var preset: BlockingPolicyPreset
    var customBaseMinutes: Double
    var customMultiplier: Double
    var customMaxHours: Double
    var minimumSessionSeconds: Double
    var priority: Int

    init(
        editingRuleID: UUID? = nil,
        targetType: BlockTargetType = .domain,
        targetValue: String = "",
        displayName: String = "",
        enabled: Bool = true,
        enforcementMode: BlockEnforcementMode = .domainNetwork,
        preset: BlockingPolicyPreset = .oneMinute,
        customBaseMinutes: Double = 1,
        customMultiplier: Double = 2,
        customMaxHours: Double = 4,
        minimumSessionSeconds: Double = 0,
        priority: Int = 0
    ) {
        self.editingRuleID = editingRuleID
        self.targetType = targetType
        self.targetValue = targetValue
        self.displayName = displayName
        self.enabled = enabled
        self.enforcementMode = enforcementMode
        self.preset = preset
        self.customBaseMinutes = customBaseMinutes
        self.customMultiplier = customMultiplier
        self.customMaxHours = customMaxHours
        self.minimumSessionSeconds = minimumSessionSeconds
        self.priority = priority
    }

    static func from(rule: BlockRule) -> BlockingRuleDraft {
        let preset = BlockingPolicyPreset.matching(rule.policy)
        return BlockingRuleDraft(
            editingRuleID: rule.id,
            targetType: rule.target.type,
            targetValue: rule.target.value,
            displayName: rule.target.displayName ?? "",
            enabled: rule.enabled,
            enforcementMode: rule.enforcementMode,
            preset: preset,
            customBaseMinutes: max(1, rule.policy.baseDurationSeconds / 60),
            customMultiplier: rule.policy.multiplier,
            customMaxHours: max(0.25, rule.policy.maxDurationSeconds / 3600),
            minimumSessionSeconds: rule.policy.minimumSessionSeconds,
            priority: rule.priority
        )
    }
}

struct BlockingRuleRow: Identifiable, Equatable, Sendable {
    var id: UUID { rule.id }
    var rule: BlockRule
    var state: BlockState?
    var isActive: Bool
    var activeUntil: Date?
    var remainingSeconds: TimeInterval
    var nextPenaltySeconds: TimeInterval

    var targetLabel: String {
        rule.target.displayName ?? rule.target.value
    }

    var enforcementLabel: String {
        switch rule.enforcementMode {
        case .monitorOnly: return "Monitor only"
        case .domainNetwork: return "Domain network"
        case .appFocus: return "App focus"
        }
    }
}

struct BlockingActiveRow: Identifiable, Equatable, Sendable {
    var id: String { "\(target.type.rawValue):\(target.value)" }
    var target: BlockTarget
    var ruleID: UUID?
    var targetLabel: String
    var blockedUntil: Date
    var remainingSeconds: TimeInterval
    var strikeCount: Int
    var enforcementMode: BlockEnforcementMode?
}

enum BlockingHelperUIState: Equatable, Sendable {
    case notNeeded
    case notInstalled
    case needsUpgrade
    case healthy
    case unhealthy(String)
}

enum BlockingViewModelError: LocalizedError, Equatable, Sendable {
    case duplicateTarget(String)
    case ruleNotFound

    var errorDescription: String? {
        switch self {
        case let .duplicateTarget(value):
            return "A blocking rule for \(value) already exists. Edit the existing rule instead."
        case .ruleNotFound:
            return "The selected blocking rule no longer exists."
        }
    }
}

struct BlockingViewModel {
    private let store: any BlockingRuleStoring
    private let helperStatusProvider: any BlockingHelperStatusProviding
    private let nowProvider: @Sendable () -> Date

    private(set) var rules: [BlockRule] = []
    private(set) var states: [BlockState] = []
    private(set) var activeBlocks: [ActiveBlock] = []
    var helperStatus: DomainBlockHelperStatus = .unavailable
    var errorMessage: String?
    private(set) var isLoading = false
    var draft = BlockingRuleDraft()
    var selectedRuleID: UUID?

    init(
        store: any BlockingRuleStoring = LiveBlockingRuleStore(),
        engine: BlockPolicyEngine = BlockPolicyEngine(),
        helperStatusProvider: any BlockingHelperStatusProviding = LiveBlockingHelperStatusProvider(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        _ = engine
        self.helperStatusProvider = helperStatusProvider
        self.nowProvider = nowProvider
    }

    var ruleRows: [BlockingRuleRow] {
        let now = nowProvider()
        let activeByTarget = Dictionary(uniqueKeysWithValues: activeBlocks.map { (TargetKey($0.state.target), $0) })
        let statesByTarget = Dictionary(uniqueKeysWithValues: states.map { (TargetKey($0.target), $0) })
        return rules.map { rule in
            let active = activeByTarget[TargetKey(rule.target)]
            let state = statesByTarget[TargetKey(rule.target)]
            let strikeCount = state?.strikeCount ?? 0
            return BlockingRuleRow(
                rule: rule,
                state: state,
                isActive: active != nil,
                activeUntil: active?.effectiveBlockedUntil,
                remainingSeconds: active.map { max(0, $0.effectiveBlockedUntil.timeIntervalSince(now)) } ?? 0,
                nextPenaltySeconds: BlockPolicyEngine.cooldownDuration(policy: rule.policy, strikeCount: strikeCount)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            if lhs.rule.enabled != rhs.rule.enabled { return lhs.rule.enabled && !rhs.rule.enabled }
            return lhs.targetLabel.localizedCaseInsensitiveCompare(rhs.targetLabel) == .orderedAscending
        }
    }

    var activeRows: [BlockingActiveRow] {
        activeBlocks.map { block in
            BlockingActiveRow(
                target: block.state.target,
                ruleID: block.rule?.id,
                targetLabel: block.state.target.displayName ?? block.state.target.value,
                blockedUntil: block.effectiveBlockedUntil,
                remainingSeconds: block.remainingSeconds,
                strikeCount: block.state.strikeCount,
                enforcementMode: block.rule?.enforcementMode
            )
        }
        .sorted { lhs, rhs in
            if lhs.blockedUntil != rhs.blockedUntil { return lhs.blockedUntil < rhs.blockedUntil }
            return lhs.targetLabel.localizedCaseInsensitiveCompare(rhs.targetLabel) == .orderedAscending
        }
    }

    var helperUIState: BlockingHelperUIState {
        let hasDomainRule = rules.contains { $0.target.type == .domain && $0.enforcementMode == .domainNetwork }
        guard hasDomainRule else { return .notNeeded }
        if let error = helperStatus.lastErrorDescription, !error.isEmpty { return .unhealthy(error) }
        switch helperStatus.installState {
        case .installed: return .healthy
        case .needsUpgrade: return .needsUpgrade
        case .notInstalled, .unavailable: return .notInstalled
        }
    }

    var emptyStateMessage: String {
        "Create app, category, or website rules. When you use something you marked as distracting, time.md starts an exponential cooldown before it can be used again."
    }

    func loaded() async -> BlockingViewModel {
        var copy = self
        await copy.load()
        return copy
    }

    mutating func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try clearExpiredBlocksInStore(now: nowProvider())
            rules = try store.fetchRules(includeDisabled: true)
            states = try store.fetchStates()
            activeBlocks = makeActiveBlocks(rules: rules, states: states, now: nowProvider())
            helperStatus = await helperStatusProvider.status()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    mutating func resetDraft(type: BlockTargetType = .domain) {
        selectedRuleID = nil
        draft = BlockingRuleDraft(targetType: type, enforcementMode: defaultEnforcementMode(for: type))
    }

    mutating func beginEditing(_ rule: BlockRule) {
        selectedRuleID = rule.id
        draft = BlockingRuleDraft.from(rule: rule)
    }

    @discardableResult
    mutating func saveDraft() throws -> BlockRule {
        let target = try BlockTarget(
            type: draft.targetType,
            value: draft.targetValue,
            displayName: draft.displayName.isEmpty ? nil : draft.displayName
        )
        if let conflict = rules.first(where: { $0.target == target && $0.id != draft.editingRuleID }) {
            throw BlockingViewModelError.duplicateTarget(conflict.target.displayName ?? conflict.target.value)
        }

        let existing = draft.editingRuleID.flatMap { id in rules.first { $0.id == id } }
        if draft.editingRuleID != nil, existing == nil {
            throw BlockingViewModelError.ruleNotFound
        }
        let policy = try draft.preset.policy(
            customBaseSeconds: draft.customBaseMinutes * 60,
            customMultiplier: draft.customMultiplier,
            customMaxSeconds: draft.customMaxHours * 3600,
            customMinimumSessionSeconds: draft.minimumSessionSeconds
        )
        let now = nowProvider()
        let rule = BlockRule(
            id: existing?.id ?? UUID(),
            target: target,
            policy: policy,
            enabled: draft.enabled,
            enforcementMode: draft.enforcementMode,
            priority: draft.priority,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try store.upsert(rule: rule)
        try reloadSynchronous()
        beginEditing(rule)
        return rule
    }

    mutating func deleteRule(id: UUID, clearState: Bool = true) throws {
        try store.deleteRule(id: id, deleteState: clearState)
        if selectedRuleID == id { resetDraft() }
        try reloadSynchronous()
    }

    mutating func toggleRule(_ rule: BlockRule, enabled: Bool) throws {
        var updated = rule
        updated.enabled = enabled
        updated.updatedAt = nowProvider()
        try store.upsert(rule: updated)
        try reloadSynchronous()
    }

    mutating func resetStrikes(for rule: BlockRule) throws {
        try store.deleteState(for: rule.target)
        try reloadSynchronous()
    }

    mutating func clearExpiredBlocks() throws {
        try clearExpiredBlocksInStore(now: nowProvider())
        try reloadSynchronous()
    }

    func countdownText(until date: Date, now: Date? = nil) -> String {
        let remaining = max(0, Int(ceil(date.timeIntervalSince(now ?? nowProvider()))))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    func durationText(_ seconds: TimeInterval) -> String {
        let rounded = Int(ceil(seconds))
        let hours = rounded / 3600
        let minutes = (rounded % 3600) / 60
        let secs = rounded % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }

    private mutating func reloadSynchronous() throws {
        try clearExpiredBlocksInStore(now: nowProvider())
        rules = try store.fetchRules(includeDisabled: true)
        states = try store.fetchStates()
        activeBlocks = makeActiveBlocks(rules: rules, states: states, now: nowProvider())
        errorMessage = nil
    }

    private func clearExpiredBlocksInStore(now: Date) throws {
        let rulesByTarget = Dictionary(grouping: try store.fetchRules(includeDisabled: true)) { TargetKey($0.target) }
        for var state in try store.fetchStates() where state.blockedUntil != nil {
            let rule = rulesByTarget[TargetKey(state.target)]?.first
            let policy = rule?.policy ?? .defaultExponential
            guard effectiveBlockedUntil(for: state, policy: policy, now: now) == nil else { continue }
            state.blockedUntil = nil
            state.updatedAt = now
            try store.upsert(state: state)
        }
    }

    private func makeActiveBlocks(rules: [BlockRule], states: [BlockState], now: Date) -> [ActiveBlock] {
        let rulesByTarget = Dictionary(grouping: rules) { TargetKey($0.target) }
        return states.compactMap { state in
            let rule = rulesByTarget[TargetKey(state.target)]?.first
            let policy = rule?.policy ?? .defaultExponential
            guard let activeUntil = effectiveBlockedUntil(for: state, policy: policy, now: now) else { return nil }
            return ActiveBlock(
                rule: rule,
                state: state,
                effectiveBlockedUntil: activeUntil,
                remainingSeconds: max(0, activeUntil.timeIntervalSince(now))
            )
        }
    }

    private func effectiveBlockedUntil(for state: BlockState, policy: BlockPolicy, now: Date) -> Date? {
        guard let blockedUntil = state.blockedUntil else { return nil }
        let effectiveUntil: Date
        if let lastBlockedAt = state.lastBlockedAt {
            effectiveUntil = min(blockedUntil, lastBlockedAt.addingTimeInterval(policy.maxDurationSeconds))
        } else {
            effectiveUntil = blockedUntil
        }
        return effectiveUntil > now ? effectiveUntil : nil
    }

    private func defaultEnforcementMode(for type: BlockTargetType) -> BlockEnforcementMode {
        switch type {
        case .domain: return .domainNetwork
        case .app, .category: return .appFocus
        }
    }
}

private struct TargetKey: Hashable {
    let type: BlockTargetType
    let value: String

    init(_ target: BlockTarget) {
        self.type = target.type
        self.value = target.value
    }
}
