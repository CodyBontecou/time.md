import Foundation

/// A normalized observation that a user accessed a blockable target. Event
/// sources can provide related targets (for example an app plus its category)
/// so the engine can resolve deterministic rule precedence without knowing
/// source-specific details.
struct BlockAccessEvent: Sendable {
    let target: BlockTarget
    let relatedTargets: [BlockTarget]
    let occurredAt: Date
    let observedDurationSeconds: TimeInterval?

    init(
        target: BlockTarget,
        relatedTargets: [BlockTarget] = [],
        occurredAt: Date = Date(),
        observedDurationSeconds: TimeInterval? = nil
    ) {
        self.target = target
        self.relatedTargets = relatedTargets
        self.occurredAt = occurredAt
        self.observedDurationSeconds = observedDurationSeconds
    }

    var candidateTargets: [BlockTarget] {
        var seen = Set<BlockTarget>()
        var ordered: [BlockTarget] = []
        for target in [target] + relatedTargets where !seen.contains(target) {
            seen.insert(target)
            ordered.append(target)
        }
        return ordered
    }
}

enum BlockPolicyDecisionKind: String, Codable, Sendable {
    /// No enabled rule matched, or the event was below the rule's minimum threshold.
    case ignored
    /// Access was accepted and a new cooldown was scheduled.
    case allowedAndStartedCooldown
    /// Access happened while a cooldown was active and was denied without mutating strike state.
    case deniedActiveBlock
}

struct BlockPolicyDecision: Sendable {
    let kind: BlockPolicyDecisionKind
    let rule: BlockRule?
    let state: BlockState?
    let blockDurationSeconds: TimeInterval?
    let blockedUntil: Date?
    let reason: String?

    static func ignored(reason: String) -> BlockPolicyDecision {
        BlockPolicyDecision(
            kind: .ignored,
            rule: nil,
            state: nil,
            blockDurationSeconds: nil,
            blockedUntil: nil,
            reason: reason
        )
    }
}

struct ActiveBlock: Hashable, Sendable {
    let rule: BlockRule?
    let state: BlockState
    let effectiveBlockedUntil: Date
    let remainingSeconds: TimeInterval
}

/// Pure policy and persistence coordinator for exponential blocking. This
/// engine does not perform OS/app enforcement; later tickets can subscribe to
/// active block state and enforce through helpers/watchers.
struct BlockPolicyEngine {
    nonisolated init() {}

    /// Returns the cooldown duration for the next allowed access. The first
    /// strike (`strikeCount == 0`) returns the base duration, the next returns
    /// `base * multiplier`, and so on. Results are rounded up to whole seconds
    /// and capped at `maxDurationSeconds` to prevent overflow/unbounded blocks.
    static func cooldownDuration(policy: BlockPolicy, strikeCount: Int) -> TimeInterval {
        let safeStrikeCount = max(0, strikeCount)
        guard policy.multiplier > 1 else {
            return ceil(min(policy.baseDurationSeconds, policy.maxDurationSeconds))
        }

        let exponent = Double(min(safeStrikeCount, 1_024))
        let raw = policy.baseDurationSeconds * pow(policy.multiplier, exponent)
        guard raw.isFinite, raw > 0 else {
            return ceil(policy.maxDurationSeconds)
        }
        return ceil(min(raw, policy.maxDurationSeconds))
    }

    func handleAccess(_ event: BlockAccessEvent) throws -> BlockPolicyDecision {
        try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
            timestamp: event.occurredAt,
            kind: .accessObserved,
            target: event.target,
            message: "Access observed"
        ))

        guard let rule = try matchingRule(for: event) else {
            return .ignored(reason: "No enabled blocking rule matched \(event.target.value).")
        }

        try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
            timestamp: event.occurredAt,
            kind: .ruleMatched,
            target: rule.target,
            ruleID: rule.id,
            message: "Rule matched for access event"
        ))

        if let duration = event.observedDurationSeconds,
           duration < rule.policy.minimumSessionSeconds {
            return BlockPolicyDecision(
                kind: .ignored,
                rule: rule,
                state: try BlockRuleStore.fetchState(for: rule.target),
                blockDurationSeconds: nil,
                blockedUntil: nil,
                reason: "Observed duration was below the rule minimum session threshold."
            )
        }

        let existingState = try BlockRuleStore.fetchState(for: rule.target)
        var state = try normalizedState(existingState, for: rule, now: event.occurredAt)

        if let activeUntil = activeBlockedUntil(for: state, policy: rule.policy, now: event.occurredAt) {
            try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
                timestamp: event.occurredAt,
                kind: .blockDenied,
                target: rule.target,
                ruleID: rule.id,
                message: "Access denied while block is active",
                metadata: ["blockedUntil": String(activeUntil.timeIntervalSince1970)]
            ))
            return BlockPolicyDecision(
                kind: .deniedActiveBlock,
                rule: rule,
                state: state,
                blockDurationSeconds: nil,
                blockedUntil: activeUntil,
                reason: "Target is blocked until \(activeUntil)."
            )
        }

        if state.blockedUntil != nil {
            state.blockedUntil = nil
            state.updatedAt = event.occurredAt
            try BlockRuleStore.upsert(state: state)
            try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
                timestamp: event.occurredAt,
                kind: .blockExpired,
                target: rule.target,
                ruleID: rule.id,
                message: "Expired block cleared before scheduling next cooldown"
            ))
        }

        if let lastAllowedAt = state.lastAllowedAt,
           rule.policy.gracePeriodSeconds > 0,
           event.occurredAt.timeIntervalSince(lastAllowedAt) < rule.policy.gracePeriodSeconds {
            return BlockPolicyDecision(
                kind: .ignored,
                rule: rule,
                state: state,
                blockDurationSeconds: nil,
                blockedUntil: nil,
                reason: "Access occurred inside the rule grace period."
            )
        }

        state = try stateAfterApplyingDecay(state, rule: rule, now: event.occurredAt)

        let duration = Self.cooldownDuration(policy: rule.policy, strikeCount: state.strikeCount)
        let blockedUntil = event.occurredAt.addingTimeInterval(duration)
        let newState = try BlockState(
            target: rule.target,
            ruleID: rule.id,
            strikeCount: min(state.strikeCount + 1, Int.max),
            blockedUntil: blockedUntil,
            lastAllowedAt: event.occurredAt,
            lastBlockedAt: event.occurredAt,
            updatedAt: event.occurredAt
        )
        try BlockRuleStore.upsert(state: newState)
        try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
            timestamp: event.occurredAt,
            kind: .blockStarted,
            target: rule.target,
            ruleID: rule.id,
            message: "Cooldown scheduled after allowed access",
            metadata: [
                "durationSeconds": String(duration),
                "blockedUntil": String(blockedUntil.timeIntervalSince1970),
                "strikeCount": String(newState.strikeCount)
            ]
        ))

        return BlockPolicyDecision(
            kind: .allowedAndStartedCooldown,
            rule: rule,
            state: newState,
            blockDurationSeconds: duration,
            blockedUntil: blockedUntil,
            reason: nil
        )
    }

    /// Returns persisted active blocks, clamping any malformed/future-skewed
    /// block window to the rule's maximum duration where possible.
    func activeBlocks(now: Date = Date()) throws -> [ActiveBlock] {
        try activeBlocks(
            rules: BlockRuleStore.fetchRules(includeDisabled: true),
            states: BlockRuleStore.fetchStates(),
            now: now
        )
    }

    func activeBlocks(rules: [BlockRule], states: [BlockState], now: Date = Date()) throws -> [ActiveBlock] {
        let rulesByTarget = Dictionary(grouping: rules) { rule in
            TargetKey(rule.target)
        }
        return states.compactMap { state in
            let rule = rulesByTarget[TargetKey(state.target)]?.first
            let policy = rule?.policy ?? .defaultExponential
            guard let activeUntil = activeBlockedUntil(for: state, policy: policy, now: now) else {
                return nil
            }
            return ActiveBlock(
                rule: rule,
                state: state,
                effectiveBlockedUntil: activeUntil,
                remainingSeconds: max(0, activeUntil.timeIntervalSince(now))
            )
        }
        .sorted { lhs, rhs in
            if lhs.effectiveBlockedUntil != rhs.effectiveBlockedUntil {
                return lhs.effectiveBlockedUntil < rhs.effectiveBlockedUntil
            }
            return lhs.state.target.value < rhs.state.target.value
        }
    }

    /// Clears expired cooldown timestamps while retaining strike history. This
    /// is safe to run on launch, wake, or before publishing enforcement state.
    @discardableResult
    func clearExpiredBlocks(now: Date = Date()) throws -> [BlockState] {
        let rulesByTarget = Dictionary(grouping: try BlockRuleStore.fetchRules(includeDisabled: true)) { rule in
            TargetKey(rule.target)
        }
        var cleared: [BlockState] = []
        for var state in try BlockRuleStore.fetchStates() {
            guard state.blockedUntil != nil else { continue }
            let policy = rulesByTarget[TargetKey(state.target)]?.first?.policy ?? .defaultExponential
            guard activeBlockedUntil(for: state, policy: policy, now: now) == nil else { continue }
            state.blockedUntil = nil
            state.updatedAt = now
            try BlockRuleStore.upsert(state: state)
            cleared.append(state)
            try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
                timestamp: now,
                kind: .blockExpired,
                target: state.target,
                ruleID: state.ruleID,
                message: "Expired block cleared by scheduler cleanup"
            ))
        }
        return cleared
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

private extension BlockPolicyEngine {
    func matchingRule(for event: BlockAccessEvent) throws -> BlockRule? {
        let candidates = event.candidateTargets
        guard !candidates.isEmpty else { return nil }
        let indexedCandidates = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { (TargetKey($0.element), $0.offset) })

        return try BlockRuleStore.fetchRules(includeDisabled: false)
            .filter { indexedCandidates[TargetKey($0.target)] != nil }
            .sorted { lhs, rhs in
                let lhsIndex = indexedCandidates[TargetKey(lhs.target)] ?? Int.max
                let rhsIndex = indexedCandidates[TargetKey(rhs.target)] ?? Int.max
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                let lhsDuration = Self.cooldownDuration(policy: lhs.policy, strikeCount: 0)
                let rhsDuration = Self.cooldownDuration(policy: rhs.policy, strikeCount: 0)
                if lhsDuration != rhsDuration { return lhsDuration > rhsDuration }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    func normalizedState(_ existingState: BlockState?, for rule: BlockRule, now: Date) throws -> BlockState {
        if var existingState {
            existingState.ruleID = existingState.ruleID ?? rule.id
            return existingState
        }
        return try BlockState(target: rule.target, ruleID: rule.id, updatedAt: now)
    }

    func stateAfterApplyingDecay(_ state: BlockState, rule: BlockRule, now: Date) throws -> BlockState {
        guard let interval = rule.policy.decayIntervalSeconds,
              interval > 0,
              let lastAllowedAt = state.lastAllowedAt,
              now >= lastAllowedAt else {
            return state
        }

        let elapsedIntervals = Int(floor(now.timeIntervalSince(lastAllowedAt) / interval))
        guard elapsedIntervals > 0 else { return state }

        var decayed = state
        switch rule.policy.decayBehavior {
        case .none:
            return state
        case .resetAfterIdle:
            decayed.strikeCount = 0
        case .stepDownAfterIdle:
            decayed.strikeCount = max(0, state.strikeCount - elapsedIntervals)
        }
        decayed.updatedAt = now
        return decayed
    }

    func activeBlockedUntil(for state: BlockState, policy: BlockPolicy, now: Date) -> Date? {
        guard let blockedUntil = state.blockedUntil else { return nil }
        let effectiveUntil: Date
        if let lastBlockedAt = state.lastBlockedAt {
            let latestAllowedUntil = lastBlockedAt.addingTimeInterval(policy.maxDurationSeconds)
            effectiveUntil = min(blockedUntil, latestAllowedUntil)
        } else {
            effectiveUntil = blockedUntil
        }
        return effectiveUntil > now ? effectiveUntil : nil
    }
}
