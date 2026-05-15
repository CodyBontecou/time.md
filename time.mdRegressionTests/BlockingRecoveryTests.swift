import XCTest
@testable import time_md

final class BlockingRecoveryTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdBlockingRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        XCTAssertEqual(setenv(BlockRuleStore.environmentOverrideKey, tempDirectory.appendingPathComponent("blocking-rules.db").path, 1), 0)
    }

    override func tearDownWithError() throws {
        _ = unsetenv(BlockRuleStore.environmentOverrideKey)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testDiagnosticsReportsHealthyDegradedAndBrokenStates() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let store = InMemoryBlockingPolicyStateStore()
        let helper = FakeDomainBlockHelperClient(installed: true)
        let hostsURL = tempDirectory.appendingPathComponent("hosts")
        let pfURL = tempDirectory.appendingPathComponent("pf.anchors/com.bontecou.time-md")
        let fileInspector = DomainBlockingManagedFileInspector(paths: DomainBlockSystemPaths(hostsURL: hostsURL, pfAnchorURL: pfURL))

        let domain = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: domain, enforcementMode: .domainNetwork)
        try store.upsert(rule: rule)
        try store.upsert(state: try BlockState(
            target: domain,
            ruleID: rule.id,
            strikeCount: 1,
            blockedUntil: Date(timeIntervalSince1970: 300),
            lastBlockedAt: now,
            updatedAt: now
        ))

        let desired = try DomainBlockDesiredState(domains: ["reddit.com"], generatedAt: now)
        let plan = DomainBlockRuleCompiler().compile(desiredState: desired)
        try plan.hostsBlock.write(to: hostsURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: pfURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plan.pfAnchorRules.write(to: pfURL, atomically: true, encoding: .utf8)
        _ = try await helper.apply(desired)

        let healthyReport = await BlockingDiagnosticsService(
            store: store,
            helper: helper,
            fileInspector: fileInspector,
            appEnforcerEnabledProvider: { true },
            now: { now }
        ).report()
        XCTAssertEqual(healthyReport.overallSeverity, .healthy)
        XCTAssertEqual(healthyReport.activeDomainCount, 1)

        let mismatchedHelper = FakeDomainBlockHelperClient(installed: true)
        let degradedReport = await BlockingDiagnosticsService(
            store: store,
            helper: mismatchedHelper,
            fileInspector: fileInspector,
            appEnforcerEnabledProvider: { true },
            now: { now }
        ).report()
        XCTAssertEqual(degradedReport.overallSeverity, .degraded)
        XCTAssertEqual(degradedReport.checks.first { $0.id == "domain-desired-state" }?.severity, .degraded)

        try DomainBlockRuleCompiler.hostsBeginMarker.write(to: hostsURL, atomically: true, encoding: .utf8)
        let brokenReport = await BlockingDiagnosticsService(
            store: store,
            helper: helper,
            fileInspector: fileInspector,
            now: { now }
        ).report()
        XCTAssertEqual(brokenReport.overallSeverity, .broken)
        XCTAssertEqual(brokenReport.checks.first { $0.id == "hosts-owned-block" }?.severity, .broken)
    }

    func testRemoveAllManagedBlocksClearsCooldownsAndHelperStateWithoutDeletingRules() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: target, enforcementMode: .domainNetwork)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: target,
            ruleID: rule.id,
            strikeCount: 3,
            blockedUntil: Date(timeIntervalSince1970: 500),
            lastBlockedAt: now,
            updatedAt: now
        ))

        let helper = FakeDomainBlockHelperClient(installed: true)
        _ = try await helper.apply(try DomainBlockDesiredState(domains: ["reddit.com"], generatedAt: now))
        let statusBeforeRemoval = await helper.status()
        XCTAssertEqual(statusBeforeRemoval.activeDomains, ["reddit.com"])

        let result = try await BlockingRecoveryService(helper: helper, now: { now }).removeAllManagedBlocks()
        XCTAssertEqual(result.clearedActiveStates, 1)
        let statusAfterRemoval = await helper.status()
        XCTAssertEqual(statusAfterRemoval.activeDomains, [])

        let state = try XCTUnwrap(BlockRuleStore.fetchState(for: target))
        XCTAssertNil(state.blockedUntil)
        XCTAssertEqual(state.strikeCount, 3)
        XCTAssertEqual(try BlockRuleStore.fetchRules(includeDisabled: true).count, 1)
        XCTAssertTrue(try BlockRuleStore.fetchAuditEvents().contains { $0.message.contains("removed all") })
    }

    func testEndToEndPolicyToDomainAndAppEnforcementWithFakes() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let domainRule = BlockRule(target: try .domain("reddit.com"), enforcementMode: .domainNetwork)
        let appRule = BlockRule(target: try .app("com.valvesoftware.steam"), enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: domainRule)
        try BlockRuleStore.upsert(rule: appRule)

        let engine = BlockPolicyEngine()
        let domainDecision = try engine.handleAccess(BlockAccessEvent(target: domainRule.target, occurredAt: now))
        XCTAssertEqual(domainDecision.kind, .allowedAndStartedCooldown)

        let helper = FakeDomainBlockHelperClient(installed: true)
        let domainResult = try await DomainBlockEnforcer(engine: engine, helper: helper, compilerClock: { now }).reconcileActiveDomainBlocks(now: now.addingTimeInterval(1))
        XCTAssertEqual(domainResult.status.activeDomains, ["reddit.com"])

        let appDecision = try engine.handleAccess(BlockAccessEvent(target: appRule.target, occurredAt: now))
        XCTAssertEqual(appDecision.kind, .allowedAndStartedCooldown)

        let controller = RecordingAppBlockController()
        let enforcer = AppBlockEnforcer(
            engine: engine,
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in nil }),
            controller: controller,
            action: .hide,
            protectedAppIdentifiers: [],
            throttleInterval: 0,
            shouldLogAuditEvents: false,
            now: { now.addingTimeInterval(1) }
        )

        let maybeAppResult = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.valvesoftware.steam"))
        let appResult = try XCTUnwrap(maybeAppResult)
        XCTAssertEqual(appResult.match.target, appRule.target)
        XCTAssertTrue(appResult.didPerformAction)
        XCTAssertEqual(controller.hiddenAppIdentifiers(), ["com.valvesoftware.steam"])
    }
}

private final class InMemoryBlockingPolicyStateStore: BlockingPolicyStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var rules: [UUID: BlockRule] = [:]
    private var states: [String: BlockState] = [:]
    private var auditEvents: [BlockAuditEvent] = []

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

    func upsert(state: BlockState) throws {
        lock.lock()
        defer { lock.unlock() }
        states[key(state.target)] = state
    }

    func appendAuditEvent(_ event: BlockAuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        auditEvents.append(event)
    }

    private func key(_ target: BlockTarget) -> String {
        "\(target.type.rawValue):\(target.value)"
    }
}

private final class RecordingAppBlockController: AppBlockControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var hiddenApps: [String] = []

    func hide(_ app: AppBlockCandidate) async throws -> Bool {
        lock.lock()
        hiddenApps.append(app.identifier)
        lock.unlock()
        return true
    }

    func terminate(_ app: AppBlockCandidate) async throws -> Bool { false }
    func activateBlockerApp() async {}

    func hiddenAppIdentifiers() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return hiddenApps
    }
}
