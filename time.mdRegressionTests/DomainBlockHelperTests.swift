import XCTest
@testable import time_md

final class DomainBlockHelperTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdDomainBlockHelperTests-\(UUID().uuidString)", isDirectory: true)
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

    func testCompilerNormalizesDomainsAndBuildsIPv4IPv6HostsEntries() throws {
        let state = try DomainBlockDesiredState(
            domains: ["https://www.Reddit.com/r/swift", "reddit.com", "news.ycombinator.com"],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let plan = DomainBlockRuleCompiler().compile(
            desiredState: state,
            resolvedAddresses: ["reddit.com": ["151.101.1.140", "not-an-ip"], "news.ycombinator.com": ["2a04:4e42::223"]]
        )

        XCTAssertEqual(plan.desiredState.domains, ["news.ycombinator.com", "reddit.com"])
        XCTAssertTrue(plan.hostsBlock.contains(DomainBlockRuleCompiler.hostsBeginMarker))
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\treddit.com"))
        XCTAssertTrue(plan.hostsBlock.contains("::1\treddit.com"))
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\twww.reddit.com"))
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\told.reddit.com"))
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\tnp.reddit.com"))
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\tnews.ycombinator.com"))
        XCTAssertTrue(plan.pfAnchorRules.contains("151.101.1.140"))
        XCTAssertTrue(plan.pfAnchorRules.contains("2a04:4e42::223"))
        XCTAssertFalse(plan.pfAnchorRules.contains("not-an-ip"))
    }

    func testCompilerIncludesObservedSubdomainHostnamesWithoutChangingActiveDomains() throws {
        let state = try DomainBlockDesiredState(
            domains: ["reddit.com"],
            additionalHostnames: ["https://old.reddit.com/r/macapps", "www.reddit.com"],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let plan = DomainBlockRuleCompiler().compile(desiredState: state)

        XCTAssertEqual(plan.desiredState.domains, ["reddit.com"])
        XCTAssertEqual(plan.desiredState.additionalHostnames, ["old.reddit.com"])
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\treddit.com"))
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\twww.reddit.com"))
        XCTAssertTrue(plan.hostsBlock.contains("0.0.0.0\told.reddit.com"))
    }

    func testHostsChangeDetectionIgnoresGeneratedTimestampOnlyChanges() throws {
        let oldPlan = try DomainBlockRuleCompiler().compile(desiredState: DomainBlockDesiredState(domains: ["reddit.com"], generatedAt: Date(timeIntervalSince1970: 1)))
        let newPlan = try DomainBlockRuleCompiler().compile(desiredState: DomainBlockDesiredState(domains: ["reddit.com"], generatedAt: Date(timeIntervalSince1970: 2)))
        let stalePlan = try DomainBlockRuleCompiler().compile(desiredState: DomainBlockDesiredState(domains: ["linkedin.com"], generatedAt: Date(timeIntervalSince1970: 1)))

        XCTAssertFalse(try DomainBlockHostsReconciler.ownedHostsBlockNeedsUpdate(existingData: Data(oldPlan.hostsBlock.utf8), desiredEntries: newPlan.hostEntries, clearing: false))
        XCTAssertTrue(try DomainBlockHostsReconciler.ownedHostsBlockNeedsUpdate(existingData: Data(stalePlan.hostsBlock.utf8), desiredEntries: newPlan.hostEntries, clearing: false))
        XCTAssertTrue(try DomainBlockHostsReconciler.ownedHostsBlockNeedsUpdate(existingData: Data(oldPlan.hostsBlock.utf8), desiredEntries: [], clearing: true))
    }

    func testHostsReconcilerPreservesUserContentAndReplacesOldOwnedBlock() throws {
        let oldBlock = """
        \(DomainBlockRuleCompiler.hostsBeginMarker)
        0.0.0.0\told.example
        \(DomainBlockRuleCompiler.hostsEndMarker)
        """
        let existing = """
        ##
        # Host Database
        ##
        127.0.0.1\tlocalhost

        \(oldBlock)

        # user entry
        10.0.0.2\tintranet.local
        """
        let newPlan = try DomainBlockRuleCompiler().compile(desiredState: DomainBlockDesiredState(domains: ["reddit.com"]))

        let reconciledData = try DomainBlockHostsReconciler.applyingOwnedBlock(newPlan.hostsBlock, to: Data(existing.utf8))
        let reconciled = String(decoding: reconciledData, as: UTF8.self)

        XCTAssertTrue(reconciled.contains("127.0.0.1\tlocalhost"))
        XCTAssertTrue(reconciled.contains("10.0.0.2\tintranet.local"))
        XCTAssertFalse(reconciled.contains("old.example"))
        XCTAssertEqual(reconciled.components(separatedBy: DomainBlockRuleCompiler.hostsBeginMarker).count - 1, 1)
        XCTAssertTrue(reconciled.contains("0.0.0.0\treddit.com"))
    }

    func testHostsReconcilerClearsOnlyOwnedBlockAndRejectsInvalidHostsFiles() throws {
        let plan = try DomainBlockRuleCompiler().compile(desiredState: DomainBlockDesiredState(domains: ["reddit.com"]))
        let existing = "127.0.0.1\tlocalhost\n\n\(plan.hostsBlock)# after\n"

        let cleared = String(decoding: try DomainBlockHostsReconciler.clearingOwnedBlock(from: Data(existing.utf8)), as: UTF8.self)
        XCTAssertEqual(cleared, "127.0.0.1\tlocalhost\n\n# after\n")

        XCTAssertThrowsError(try DomainBlockHostsReconciler.clearingOwnedBlock(from: Data([0xff, 0xfe]))) { error in
            XCTAssertEqual(error as? DomainBlockHelperError, .hostsFileNotUTF8)
        }
    }

    func testFakeHelperInstallApplyClearRepairAndFailureModes() async throws {
        let helper = FakeDomainBlockHelperClient(installed: false)

        do {
            _ = try await helper.installOrUpgrade(withConsent: .denied)
            XCTFail("Expected denied install to throw")
        } catch {
            XCTAssertEqual(error as? DomainBlockHelperError, .authorizationDenied)
        }

        _ = try await helper.installOrUpgrade(withConsent: .approvedForDomainBlocking)
        let desired = try DomainBlockDesiredState(domains: ["*.reddit.com"], generatedAt: Date(timeIntervalSince1970: 100))
        let applied = try await helper.apply(desired)
        XCTAssertEqual(applied.status.activeDomains, ["reddit.com"])
        XCTAssertTrue(applied.changedHosts)

        let repeated = try await helper.apply(desired)
        XCTAssertFalse(repeated.changedHosts)
        XCTAssertFalse(repeated.changedPFAnchor)

        let repaired = try await helper.repair(try DomainBlockDesiredState(domains: ["example.com"], generatedAt: Date(timeIntervalSince1970: 101)))
        XCTAssertEqual(repaired.status.activeDomains, ["example.com"])

        let cleared = try await helper.clearAll()
        XCTAssertEqual(cleared.status.activeDomains, [])
    }

    func testEnforcerAddsRecentlyObservedSubdomainsToHostsPlan() async throws {
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: target, enforcementMode: .domainNetwork)
        let now = Date(timeIntervalSince1970: 100)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: target,
            ruleID: rule.id,
            strikeCount: 1,
            blockedUntil: Date(timeIntervalSince1970: 300),
            lastBlockedAt: now,
            updatedAt: now
        ))
        try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
            timestamp: now.addingTimeInterval(-600),
            kind: .accessObserved,
            target: try .domain("https://old.reddit.com/r/macapps"),
            message: "Access observed"
        ))

        let helper = FakeDomainBlockHelperClient(installed: true)
        let enforcer = DomainBlockEnforcer(
            engine: BlockPolicyEngine(),
            helper: helper,
            compilerClock: { now }
        )

        let result = try await enforcer.reconcileActiveDomainBlocks(now: now)
        let plan = await helper.currentPlan
        XCTAssertEqual(result.status.activeDomains, ["reddit.com"])
        XCTAssertTrue(plan?.hostsBlock.contains("0.0.0.0\told.reddit.com") ?? false)
    }

    func testEnforcerPublishesOnlyActiveDomainNetworkBlocks() async throws {
        let activeDomain = try BlockTarget.domain("reddit.com")
        let monitorOnlyDomain = try BlockTarget.domain("example.com")
        let appTarget = try BlockTarget.app("com.example.Game")

        let domainRule = BlockRule(target: activeDomain, enforcementMode: .domainNetwork)
        let monitorRule = BlockRule(target: monitorOnlyDomain, enforcementMode: .monitorOnly)
        let appRule = BlockRule(target: appTarget, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: domainRule)
        try BlockRuleStore.upsert(rule: monitorRule)
        try BlockRuleStore.upsert(rule: appRule)
        try BlockRuleStore.upsert(state: try BlockState(target: activeDomain, ruleID: domainRule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 100)))
        try BlockRuleStore.upsert(state: try BlockState(target: monitorOnlyDomain, ruleID: monitorRule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 100)))
        try BlockRuleStore.upsert(state: try BlockState(target: appTarget, ruleID: appRule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 100)))

        let helper = FakeDomainBlockHelperClient(installed: true)
        let enforcer = DomainBlockEnforcer(
            engine: BlockPolicyEngine(),
            helper: helper,
            compilerClock: { Date(timeIntervalSince1970: 150) }
        )

        let result = try await enforcer.reconcileActiveDomainBlocks(now: Date(timeIntervalSince1970: 150))
        XCTAssertEqual(result.status.activeDomains, ["reddit.com"])
    }

    func testLaunchDaemonHelperStatusUsesInjectedInstallArtifacts() async throws {
        let stateDirectory = tempDirectory.appendingPathComponent("daemon-state", isDirectory: true)
        let helperScript = tempDirectory.appendingPathComponent("helper")
        let plist = tempDirectory.appendingPathComponent("helper.plist")
        let config = DomainBlockLaunchDaemonConfiguration(
            stateDirectoryURL: stateDirectory,
            helperScriptURL: helperScript,
            launchDaemonPlistURL: plist
        )
        let helper = PrivilegedDomainBlockHelperClient(
            paths: DomainBlockSystemPaths(
                hostsURL: tempDirectory.appendingPathComponent("hosts"),
                pfAnchorURL: tempDirectory.appendingPathComponent("pf-anchor")
            ),
            configuration: config
        )

        var status = await helper.status()
        XCTAssertEqual(status.installState, .notInstalled)

        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try "HELPER_VERSION=old\n".write(to: helperScript, atomically: true, encoding: .utf8)
        try "plist\n".write(to: plist, atomically: true, encoding: .utf8)
        status = await helper.status()
        XCTAssertEqual(status.installState, .needsUpgrade)
        XCTAssertEqual(status.helperVersion, "old")

        try "HELPER_VERSION=2\n".write(to: helperScript, atomically: true, encoding: .utf8)
        try """
        requestID=test-request
        result=ok
        helperVersion=2
        appVersion=2.4.0
        generatedAt=1970-01-01T00:00:00.000Z
        activeDomains=reddit.com,old.reddit.com
        changedHosts=true
        changedPFAnchor=false
        lastErrorDescription=
        """.write(to: config.statusURL, atomically: true, encoding: .utf8)

        status = await helper.status()
        XCTAssertEqual(status.installState, .installed)
        XCTAssertEqual(status.activeDomains, ["reddit.com", "old.reddit.com"])
        XCTAssertNil(status.lastErrorDescription)
    }

    func testLaunchDaemonHelperApplyDoesNotPromptWhenHelperIsMissing() async throws {
        let config = DomainBlockLaunchDaemonConfiguration(
            stateDirectoryURL: tempDirectory.appendingPathComponent("missing-state", isDirectory: true),
            helperScriptURL: tempDirectory.appendingPathComponent("missing-helper"),
            launchDaemonPlistURL: tempDirectory.appendingPathComponent("missing-helper.plist")
        )
        let helper = PrivilegedDomainBlockHelperClient(
            paths: DomainBlockSystemPaths(
                hostsURL: tempDirectory.appendingPathComponent("missing-hosts"),
                pfAnchorURL: tempDirectory.appendingPathComponent("missing-pf-anchor")
            ),
            configuration: config
        )
        let desired = try DomainBlockDesiredState(domains: ["reddit.com"], generatedAt: Date(timeIntervalSince1970: 123))

        do {
            _ = try await helper.apply(desired)
            XCTFail("Expected missing helper to throw")
        } catch let error as DomainBlockHelperError {
            guard case .helperUnavailable = error else {
                return XCTFail("Expected helperUnavailable, got \(error)")
            }
        }
    }

    func testLocalHelperUsesInjectedFilesAndIsIdempotent() async throws {
        let hostsURL = tempDirectory.appendingPathComponent("hosts")
        let anchorURL = tempDirectory.appendingPathComponent("pf.anchors/com.bontecou.time-md")
        try "127.0.0.1\tlocalhost\n".write(to: hostsURL, atomically: true, encoding: .utf8)
        let helper = LocalDomainBlockHelperClient(
            paths: DomainBlockSystemPaths(hostsURL: hostsURL, pfAnchorURL: anchorURL),
            commandRunner: nil
        )

        let desired = try DomainBlockDesiredState(domains: ["reddit.com"], generatedAt: Date(timeIntervalSince1970: 123))
        let first = try await helper.apply(desired)
        let second = try await helper.apply(desired)

        XCTAssertTrue(first.changedHosts)
        XCTAssertTrue(first.changedPFAnchor)
        XCTAssertFalse(second.changedHosts)
        XCTAssertFalse(second.changedPFAnchor)
        let hosts = try String(contentsOf: hostsURL, encoding: .utf8)
        XCTAssertTrue(hosts.contains("127.0.0.1\tlocalhost"))
        XCTAssertTrue(hosts.contains("0.0.0.0\treddit.com"))

        _ = try await helper.clearAll()
        let clearedHosts = try String(contentsOf: hostsURL, encoding: .utf8)
        XCTAssertFalse(clearedHosts.contains(DomainBlockRuleCompiler.hostsBeginMarker))
        XCTAssertTrue(clearedHosts.contains("127.0.0.1\tlocalhost"))
    }
}
