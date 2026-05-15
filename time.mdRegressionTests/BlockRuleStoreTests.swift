import SQLite3
import XCTest
@testable import time_md

final class BlockRuleStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdBlockingTests-\(UUID().uuidString)", isDirectory: true)
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

    func testTargetNormalizationForDomainsAppsAndCategories() throws {
        let reddit = try BlockTarget.domain(" https://www.Reddit.com/r/swift?sort=top ")
        XCTAssertEqual(reddit.type, .domain)
        XCTAssertEqual(reddit.value, "reddit.com")

        let app = try BlockTarget.app("  COM.APPLE.SAFARI  ")
        XCTAssertEqual(app.value, "com.apple.safari")
        XCTAssertEqual(app.displayName, "COM.APPLE.SAFARI")

        let fallbackAppName = try BlockTarget.app("  Steam Helper  ")
        XCTAssertEqual(fallbackAppName.value, "Steam Helper")
        XCTAssertEqual(fallbackAppName.displayName, "Steam Helper")

        let category = try BlockTarget.category("  Social   Networking  ")
        XCTAssertEqual(category.value, "social networking")
        XCTAssertEqual(category.displayName, "Social Networking")
    }

    func testInvalidTargetsAndPoliciesThrowActionableErrors() throws {
        XCTAssertThrowsError(try BlockTarget.domain("   ")) { error in
            XCTAssertTrue(error.localizedDescription.contains("cannot be empty"))
        }

        XCTAssertThrowsError(try BlockTarget.domain("not a domain")) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a valid domain"))
        }

        XCTAssertThrowsError(try BlockPolicy(baseDurationSeconds: 0, multiplier: 2, maxDurationSeconds: 60)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Base block duration"))
        }

        XCTAssertThrowsError(try BlockPolicy(baseDurationSeconds: 60, multiplier: 0.5, maxDurationSeconds: 60)) { error in
            XCTAssertTrue(error.localizedDescription.contains("multiplier"))
        }
    }

    func testRuleCRUDPersistsAcrossOperations() throws {
        XCTAssertTrue(try BlockRuleStore.fetchRules().isEmpty)

        let redditRule = BlockRule(
            target: try .domain("reddit.com"),
            policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 3_600),
            priority: 10,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let gamesRule = BlockRule(
            target: try .category("Games"),
            policy: try BlockPolicy(baseDurationSeconds: 300, multiplier: 2, maxDurationSeconds: 7_200),
            enabled: false,
            priority: 1,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try BlockRuleStore.upsert(rule: redditRule)
        try BlockRuleStore.upsert(rule: gamesRule)

        let allRules = try BlockRuleStore.fetchRules()
        XCTAssertEqual(allRules.map(\.id), [redditRule.id, gamesRule.id])
        XCTAssertEqual(allRules.first?.target.value, "reddit.com")
        XCTAssertEqual(allRules.first?.enforcementMode, .domainNetwork)
        XCTAssertEqual(allRules.last?.enforcementMode, .appFocus)

        let enabledOnly = try BlockRuleStore.fetchRules(includeDisabled: false)
        XCTAssertEqual(enabledOnly.map(\.id), [redditRule.id])

        var updated = redditRule
        updated.enabled = false
        updated.priority = 99
        updated.updatedAt = Date(timeIntervalSince1970: 300)
        try BlockRuleStore.upsert(rule: updated)

        let refetched = try XCTUnwrap(BlockRuleStore.fetchRule(id: redditRule.id))
        XCTAssertFalse(refetched.enabled)
        XCTAssertEqual(refetched.priority, 99)
        XCTAssertEqual(refetched.updatedAt.timeIntervalSince1970, 300, accuracy: 0.001)

        try BlockRuleStore.deleteRule(id: redditRule.id)
        XCTAssertNil(try BlockRuleStore.fetchRule(id: redditRule.id))
        XCTAssertEqual(try BlockRuleStore.fetchRules().map(\.id), [gamesRule.id])
    }

    func testBlockStatePersistsIndependentlyFromRuleDefinitions() throws {
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: target)
        try BlockRuleStore.upsert(rule: rule)

        let state = try BlockState(
            target: target,
            ruleID: rule.id,
            strikeCount: 3,
            blockedUntil: Date(timeIntervalSince1970: 1_000),
            lastAllowedAt: Date(timeIntervalSince1970: 900),
            lastBlockedAt: Date(timeIntervalSince1970: 950),
            updatedAt: Date(timeIntervalSince1970: 975)
        )
        try BlockRuleStore.upsert(state: state)

        try BlockRuleStore.deleteRule(id: rule.id)

        let persistedState = try XCTUnwrap(BlockRuleStore.fetchState(for: target))
        XCTAssertEqual(persistedState.ruleID, rule.id)
        XCTAssertEqual(persistedState.strikeCount, 3)
        XCTAssertEqual(try XCTUnwrap(persistedState.blockedUntil).timeIntervalSince1970, 1_000, accuracy: 0.001)

        try BlockRuleStore.deleteState(for: target)
        XCTAssertNil(try BlockRuleStore.fetchState(for: target))
    }

    func testSchemaCreationIsIdempotentAndUsesIsolatedDatabase() throws {
        let firstURL = try BlockRuleStore.databaseURL()
        let secondURL = try BlockRuleStore.databaseURL()

        XCTAssertEqual(firstURL, secondURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(firstURL.path.hasPrefix(tempDirectory.path))
        XCTAssertNoThrow(try BlockRuleStore.fetchRules())
        XCTAssertNoThrow(try BlockRuleStore.fetchStates())
        XCTAssertNoThrow(try BlockRuleStore.fetchAuditEvents())
    }

    func testCorruptRowsAreSkippedDuringFetch() throws {
        let validRule = BlockRule(target: try .domain("reddit.com"))
        try BlockRuleStore.upsert(rule: validRule)

        let dbURL = try BlockRuleStore.databaseURL()
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dbURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil), SQLITE_OK)
        guard let db = handle else {
            return XCTFail("Expected SQLite handle")
        }
        defer { sqlite3_close(db) }

        let insertCorruptRuleSQL = """
        INSERT INTO block_rules (
            id, target_type, target_value, policy_json, enabled, enforcement_mode,
            priority, created_at, updated_at
        ) VALUES ('not-a-uuid', 'unknown-target', '', '{bad json', 1, 'missing-mode', 0, 0, 0)
        """
        XCTAssertEqual(sqlite3_exec(db, insertCorruptRuleSQL, nil, nil, nil), SQLITE_OK)

        let insertCorruptStateSQL = """
        INSERT INTO block_states (
            target_type, target_value, strike_count, updated_at
        ) VALUES ('domain', 'reddit.com', -5, 0)
        """
        XCTAssertEqual(sqlite3_exec(db, insertCorruptStateSQL, nil, nil, nil), SQLITE_OK)

        let rules = try BlockRuleStore.fetchRules()
        XCTAssertEqual(rules.map(\.id), [validRule.id])
        XCTAssertTrue(try BlockRuleStore.fetchStates().isEmpty)
    }

    func testAuditEventsRoundTrip() throws {
        let target = try BlockTarget.category("Entertainment")
        let ruleID = UUID()
        let event = BlockAuditEvent(
            timestamp: Date(timeIntervalSince1970: 42),
            kind: .ruleCreated,
            target: target,
            ruleID: ruleID,
            message: "Created rule",
            metadata: ["source": "test"]
        )

        try BlockRuleStore.appendAuditEvent(event)

        let events = try BlockRuleStore.fetchAuditEvents()
        let fetched = try XCTUnwrap(events.first)
        XCTAssertEqual(fetched.id, event.id)
        XCTAssertEqual(fetched.timestamp.timeIntervalSince1970, 42, accuracy: 0.001)
        XCTAssertEqual(fetched.kind, .ruleCreated)
        XCTAssertEqual(fetched.target, target)
        XCTAssertEqual(fetched.ruleID, ruleID)
        XCTAssertEqual(fetched.message, "Created rule")
        XCTAssertEqual(fetched.metadata, ["source": "test"])
    }
}
