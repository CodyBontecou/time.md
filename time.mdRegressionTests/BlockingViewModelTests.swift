import XCTest
@testable import time_md

final class BlockingViewModelTests: XCTestCase {
    func testRuleCreationNormalizesAndRejectsDuplicateTargets() throws {
        let store = InMemoryBlockingRuleStore()
        var viewModel = BlockingViewModel(store: store, helperStatusProvider: StaticBlockingHelperStatusProvider(.unavailable), nowProvider: { Date(timeIntervalSince1970: 100) })

        viewModel.draft = BlockingRuleDraft(targetType: .domain, targetValue: "https://www.Reddit.com/r/swift", preset: .oneMinute)
        let rule = try viewModel.saveDraft()
        XCTAssertEqual(rule.target.value, "reddit.com")
        XCTAssertEqual(rule.enforcementMode, .domainNetwork)
        XCTAssertEqual(viewModel.ruleRows.map(\.targetLabel), ["reddit.com"])

        viewModel.draft = BlockingRuleDraft(targetType: .domain, targetValue: "reddit.com", preset: .fiveMinutes)
        XCTAssertThrowsError(try viewModel.saveDraft()) { error in
            XCTAssertEqual(error as? BlockingViewModelError, .duplicateTarget("reddit.com"))
        }
    }

    func testActiveCountdownRowsSortByUnlockAndFormatDurations() throws {
        let store = InMemoryBlockingRuleStore()
        let now = Date(timeIntervalSince1970: 100)
        let reddit = BlockRule(target: try .domain("reddit.com"), enforcementMode: .domainNetwork)
        let steam = BlockRule(target: try .app("com.valvesoftware.steam"), enforcementMode: .appFocus)
        try store.upsert(rule: reddit)
        try store.upsert(rule: steam)
        try store.upsert(state: try BlockState(target: reddit.target, ruleID: reddit.id, strikeCount: 2, blockedUntil: Date(timeIntervalSince1970: 300), updatedAt: now))
        try store.upsert(state: try BlockState(target: steam.target, ruleID: steam.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 160), updatedAt: now))

        var viewModel = BlockingViewModel(store: store, helperStatusProvider: StaticBlockingHelperStatusProvider(.unavailable), nowProvider: { now })
        try viewModel.clearExpiredBlocks()

        XCTAssertEqual(viewModel.activeRows.map(\.targetLabel), ["com.valvesoftware.steam", "reddit.com"])
        XCTAssertEqual(viewModel.countdownText(until: Date(timeIntervalSince1970: 160)), "1m 0s")
        XCTAssertEqual(viewModel.countdownText(until: Date(timeIntervalSince1970: 7_500)), "2h 3m")
        XCTAssertEqual(viewModel.ruleRows.first { $0.rule.id == reddit.id }?.nextPenaltySeconds, 240)
    }

    func testHelperStatusStatesReflectDomainRuleNeeds() throws {
        let store = InMemoryBlockingRuleStore()
        var viewModel = BlockingViewModel(store: store, helperStatusProvider: StaticBlockingHelperStatusProvider(.unavailable))
        XCTAssertEqual(viewModel.helperUIState, .notNeeded)

        try store.upsert(rule: BlockRule(target: try .domain("reddit.com"), enforcementMode: .domainNetwork))
        viewModel.helperStatus = DomainBlockHelperStatus(installState: .notInstalled, helperVersion: nil, appVersion: nil, activeDomains: [], lastAppliedAt: nil, lastErrorDescription: nil)
        try viewModel.clearExpiredBlocks()
        XCTAssertEqual(viewModel.helperUIState, .notInstalled)

        viewModel.helperStatus = DomainBlockHelperStatus(installState: .needsUpgrade, helperVersion: "1", appVersion: "2", activeDomains: [], lastAppliedAt: nil, lastErrorDescription: nil)
        XCTAssertEqual(viewModel.helperUIState, .needsUpgrade)

        viewModel.helperStatus = DomainBlockHelperStatus(installState: .installed, helperVersion: "2", appVersion: "2", activeDomains: [], lastAppliedAt: nil, lastErrorDescription: nil)
        XCTAssertEqual(viewModel.helperUIState, .healthy)

        viewModel.helperStatus = DomainBlockHelperStatus(installState: .installed, helperVersion: "2", appVersion: "2", activeDomains: [], lastAppliedAt: nil, lastErrorDescription: "pfctl failed")
        XCTAssertEqual(viewModel.helperUIState, .unhealthy("pfctl failed"))
    }

    func testEditDeleteAndResetFlowsUseInjectedStore() throws {
        let store = InMemoryBlockingRuleStore()
        let now = Date(timeIntervalSince1970: 100)
        let rule = BlockRule(target: try .app("com.example.Game"), policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600), enforcementMode: .appFocus)
        try store.upsert(rule: rule)
        try store.upsert(state: try BlockState(target: rule.target, ruleID: rule.id, strikeCount: 3, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: now))

        var viewModel = BlockingViewModel(store: store, helperStatusProvider: StaticBlockingHelperStatusProvider(.unavailable), nowProvider: { now })
        try viewModel.clearExpiredBlocks()
        viewModel.beginEditing(rule)
        viewModel.draft.enabled = false
        viewModel.draft.preset = .fiveMinutes
        let updated = try viewModel.saveDraft()
        XCTAssertFalse(updated.enabled)
        XCTAssertEqual(updated.policy.baseDurationSeconds, 300)

        try viewModel.resetStrikes(for: updated)
        XCTAssertNil(try store.fetchStates().first { $0.target == updated.target })

        try store.upsert(state: try BlockState(target: updated.target, ruleID: updated.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: now))
        try viewModel.deleteRule(id: updated.id)
        XCTAssertTrue(try store.fetchRules(includeDisabled: true).isEmpty)
        XCTAssertTrue(try store.fetchStates().isEmpty)
    }

    func testExpiredBlocksAreClearedWithoutRemovingStrikeHistory() throws {
        let store = InMemoryBlockingRuleStore()
        let target = try BlockTarget.category("Social")
        let rule = BlockRule(target: target, enforcementMode: .appFocus)
        try store.upsert(rule: rule)
        try store.upsert(state: try BlockState(target: target, ruleID: rule.id, strikeCount: 4, blockedUntil: Date(timeIntervalSince1970: 90), updatedAt: Date(timeIntervalSince1970: 80)))

        var viewModel = BlockingViewModel(store: store, helperStatusProvider: StaticBlockingHelperStatusProvider(.unavailable), nowProvider: { Date(timeIntervalSince1970: 100) })
        try viewModel.clearExpiredBlocks()

        let state = try XCTUnwrap(store.fetchStates().first)
        XCTAssertNil(state.blockedUntil)
        XCTAssertEqual(state.strikeCount, 4)
        XCTAssertTrue(viewModel.activeRows.isEmpty)
    }
}

private final class InMemoryBlockingRuleStore: BlockingRuleStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var rules: [UUID: BlockRule] = [:]
    private var states: [String: BlockState] = [:]

    func fetchRules(includeDisabled: Bool) throws -> [BlockRule] {
        lock.lock()
        defer { lock.unlock() }
        return rules.values
            .filter { includeDisabled || $0.enabled }
            .sorted { $0.target.value < $1.target.value }
    }

    func fetchStates() throws -> [BlockState] {
        lock.lock()
        defer { lock.unlock() }
        return states.values.sorted { $0.target.value < $1.target.value }
    }

    func upsert(rule: BlockRule) throws {
        lock.lock()
        defer { lock.unlock() }
        rules[rule.id] = rule
    }

    func deleteRule(id: UUID, deleteState: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let rule = rules.removeValue(forKey: id), deleteState else { return }
        states.removeValue(forKey: key(rule.target))
    }

    func deleteState(for target: BlockTarget) throws {
        lock.lock()
        defer { lock.unlock() }
        states.removeValue(forKey: key(target))
    }

    func upsert(state: BlockState) throws {
        lock.lock()
        defer { lock.unlock() }
        states[key(state.target)] = state
    }

    private func key(_ target: BlockTarget) -> String {
        "\(target.type.rawValue):\(target.value)"
    }
}
