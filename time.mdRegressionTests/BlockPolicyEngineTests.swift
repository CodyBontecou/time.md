import XCTest
@testable import time_md

final class BlockPolicyEngineTests: XCTestCase {
    private var tempDirectory: URL!
    private let engine = BlockPolicyEngine()

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdPolicyEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let dbPath = tempDirectory.appendingPathComponent("blocking-rules.db").path
        XCTAssertEqual(setenv(BlockRuleStore.environmentOverrideKey, dbPath, 1), 0)
    }

    override func tearDownWithError() throws {
        _ = unsetenv(BlockRuleStore.environmentOverrideKey)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testExponentialProgressionSchedulesOneTwoFourMinuteCooldowns() throws {
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(
            target: target,
            policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 10 * 60),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        try BlockRuleStore.upsert(rule: rule)

        let first = try engine.handleAccess(BlockAccessEvent(target: target, occurredAt: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(first.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(first.blockDurationSeconds, 60)
        XCTAssertEqual(first.blockedUntil?.timeIntervalSince1970, 160)
        XCTAssertEqual(first.state?.strikeCount, 1)

        let second = try engine.handleAccess(BlockAccessEvent(target: target, occurredAt: Date(timeIntervalSince1970: 161)))
        XCTAssertEqual(second.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(second.blockDurationSeconds, 120)
        XCTAssertEqual(second.blockedUntil?.timeIntervalSince1970, 281)
        XCTAssertEqual(second.state?.strikeCount, 2)

        let third = try engine.handleAccess(BlockAccessEvent(target: target, occurredAt: Date(timeIntervalSince1970: 282)))
        XCTAssertEqual(third.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(third.blockDurationSeconds, 240)
        XCTAssertEqual(third.blockedUntil?.timeIntervalSince1970, 522)
        XCTAssertEqual(third.state?.strikeCount, 3)
    }

    func testActiveBlockAttemptIsDeniedWithoutShorteningOrIncreasingStrikeCount() throws {
        let target = try BlockTarget.domain("reddit.com")
        try BlockRuleStore.upsert(rule: BlockRule(
            target: target,
            policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600)
        ))

        _ = try engine.handleAccess(BlockAccessEvent(target: target, occurredAt: Date(timeIntervalSince1970: 100)))

        let denied = try engine.handleAccess(BlockAccessEvent(target: target, occurredAt: Date(timeIntervalSince1970: 120)))
        XCTAssertEqual(denied.kind, .deniedActiveBlock)
        XCTAssertEqual(denied.blockedUntil?.timeIntervalSince1970, 160)
        XCTAssertEqual(denied.state?.strikeCount, 1)

        let state = try XCTUnwrap(BlockRuleStore.fetchState(for: target))
        XCTAssertEqual(state.strikeCount, 1)
        XCTAssertEqual(try XCTUnwrap(state.blockedUntil).timeIntervalSince1970, 160, accuracy: 0.001)
    }

    func testMaxCapFixedMultiplierAndOverflowProtection() throws {
        let capped = try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 180)
        XCTAssertEqual(BlockPolicyEngine.cooldownDuration(policy: capped, strikeCount: 0), 60)
        XCTAssertEqual(BlockPolicyEngine.cooldownDuration(policy: capped, strikeCount: 1), 120)
        XCTAssertEqual(BlockPolicyEngine.cooldownDuration(policy: capped, strikeCount: 2), 180)
        XCTAssertEqual(BlockPolicyEngine.cooldownDuration(policy: capped, strikeCount: 2_000), 180)

        let fixed = try BlockPolicy(baseDurationSeconds: 45, multiplier: 1, maxDurationSeconds: 300)
        XCTAssertEqual(BlockPolicyEngine.cooldownDuration(policy: fixed, strikeCount: 0), 45)
        XCTAssertEqual(BlockPolicyEngine.cooldownDuration(policy: fixed, strikeCount: 20), 45)
    }

    func testResetAndStepDownDecayBehavior() throws {
        let target = try BlockTarget.domain("reddit.com")
        let resetRule = BlockRule(
            target: target,
            policy: try BlockPolicy(
                baseDurationSeconds: 60,
                multiplier: 2,
                maxDurationSeconds: 600,
                decayBehavior: .resetAfterIdle,
                decayIntervalSeconds: 300
            )
        )
        try BlockRuleStore.upsert(rule: resetRule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: target,
            ruleID: resetRule.id,
            strikeCount: 4,
            lastAllowedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        ))

        let resetDecision = try engine.handleAccess(BlockAccessEvent(target: target, occurredAt: Date(timeIntervalSince1970: 401)))
        XCTAssertEqual(resetDecision.blockDurationSeconds, 60)
        XCTAssertEqual(resetDecision.state?.strikeCount, 1)

        let appTarget = try BlockTarget.app("com.valvesoftware.steam")
        let stepRule = BlockRule(
            target: appTarget,
            policy: try BlockPolicy(
                baseDurationSeconds: 60,
                multiplier: 2,
                maxDurationSeconds: 600,
                decayBehavior: .stepDownAfterIdle,
                decayIntervalSeconds: 300
            )
        )
        try BlockRuleStore.upsert(rule: stepRule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: appTarget,
            ruleID: stepRule.id,
            strikeCount: 4,
            lastAllowedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        ))

        let stepDecision = try engine.handleAccess(BlockAccessEvent(target: appTarget, occurredAt: Date(timeIntervalSince1970: 701)))
        XCTAssertEqual(stepDecision.blockDurationSeconds, 240)
        XCTAssertEqual(stepDecision.state?.strikeCount, 3)
    }

    func testActiveBlocksSurviveRestartAndExpiredBlocksClear() throws {
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: target, policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600))
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: target,
            ruleID: rule.id,
            strikeCount: 2,
            blockedUntil: Date(timeIntervalSince1970: 200),
            lastAllowedAt: Date(timeIntervalSince1970: 100),
            lastBlockedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        ))

        let restartedEngine = BlockPolicyEngine()
        let active = try restartedEngine.activeBlocks(now: Date(timeIntervalSince1970: 150))
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.effectiveBlockedUntil.timeIntervalSince1970, 200)
        XCTAssertEqual(active.first?.remainingSeconds, 50)

        let cleared = try restartedEngine.clearExpiredBlocks(now: Date(timeIntervalSince1970: 201))
        XCTAssertEqual(cleared.map(\.target), [target])
        XCTAssertTrue(try restartedEngine.activeBlocks(now: Date(timeIntervalSince1970: 201)).isEmpty)
        XCTAssertNil(try BlockRuleStore.fetchState(for: target)?.blockedUntil)
    }

    func testRulePrecedenceUsesEventSpecificityBeforePriority() throws {
        let appTarget = try BlockTarget.app("com.valvesoftware.steam")
        let categoryTarget = try BlockTarget.category("Games")
        let appRule = BlockRule(
            target: appTarget,
            policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600),
            priority: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let categoryRule = BlockRule(
            target: categoryTarget,
            policy: try BlockPolicy(baseDurationSeconds: 300, multiplier: 2, maxDurationSeconds: 600),
            priority: 100,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        try BlockRuleStore.upsert(rule: categoryRule)
        try BlockRuleStore.upsert(rule: appRule)

        let decision = try engine.handleAccess(BlockAccessEvent(
            target: appTarget,
            relatedTargets: [categoryTarget],
            occurredAt: Date(timeIntervalSince1970: 1_000)
        ))

        XCTAssertEqual(decision.rule?.id, appRule.id)
        XCTAssertEqual(decision.blockDurationSeconds, 60)
    }

    func testClockSkewClampsMalformedFutureBlockToMaxDuration() throws {
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: target, policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600))
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: target,
            ruleID: rule.id,
            strikeCount: 99,
            blockedUntil: Date(timeIntervalSince1970: 10_000),
            lastBlockedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        ))

        let active = try engine.activeBlocks(now: Date(timeIntervalSince1970: 150))
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.effectiveBlockedUntil.timeIntervalSince1970, 700)
        XCTAssertEqual(active.first?.remainingSeconds, 550)

        let cleared = try engine.clearExpiredBlocks(now: Date(timeIntervalSince1970: 701))
        XCTAssertEqual(cleared.map(\.target), [target])
        XCTAssertTrue(try engine.activeBlocks(now: Date(timeIntervalSince1970: 701)).isEmpty)
        XCTAssertNil(try BlockRuleStore.fetchState(for: target)?.blockedUntil)
    }

    func testUnmatchedAndSubThresholdEventsAreIgnored() throws {
        let unknownDecision = try engine.handleAccess(BlockAccessEvent(
            target: try .domain("example.com"),
            occurredAt: Date(timeIntervalSince1970: 1)
        ))
        XCTAssertEqual(unknownDecision.kind, .ignored)

        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(
            target: target,
            policy: try BlockPolicy(
                baseDurationSeconds: 60,
                multiplier: 2,
                maxDurationSeconds: 600,
                minimumSessionSeconds: 5
            )
        )
        try BlockRuleStore.upsert(rule: rule)

        let shortDecision = try engine.handleAccess(BlockAccessEvent(
            target: target,
            occurredAt: Date(timeIntervalSince1970: 10),
            observedDurationSeconds: 2
        ))
        XCTAssertEqual(shortDecision.kind, .ignored)
        XCTAssertNil(try BlockRuleStore.fetchState(for: target))
    }
}
