import XCTest
@testable import time_md

final class AppBlockingEventTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdAppBlockingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        XCTAssertEqual(setenv(BlockRuleStore.environmentOverrideKey, tempDirectory.appendingPathComponent("blocking-rules.db").path, 1), 0)
        XCTAssertEqual(setenv("SCREENTIME_CATEGORY_MAPPINGS_DB_PATH", tempDirectory.appendingPathComponent("category-mappings.db").path, 1), 0)
    }

    override func tearDownWithError() throws {
        _ = unsetenv(BlockRuleStore.environmentOverrideKey)
        _ = unsetenv("SCREENTIME_CATEGORY_MAPPINGS_DB_PATH")
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testDirectAppRuleTriggersCooldownFromCompletedSession() throws {
        let appTarget = try BlockTarget.app("com.reddit.Reddit")
        let rule = BlockRule(
            target: appTarget,
            policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600)
        )
        try BlockRuleStore.upsert(rule: rule)

        let processor = AppBlockingEventProcessor(resolver: resolver())
        let decision = try processor.process(session(appIdentifier: "COM.REDDIT.REDDIT", startedAt: 100, duration: 10))

        XCTAssertEqual(decision?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(decision?.rule?.id, rule.id)
        XCTAssertEqual(decision?.blockDurationSeconds, 60)
        XCTAssertEqual(decision?.blockedUntil?.timeIntervalSince1970, 170)

        let state = try XCTUnwrap(BlockRuleStore.fetchState(for: appTarget))
        XCTAssertEqual(state.strikeCount, 1)
        XCTAssertEqual(try XCTUnwrap(state.blockedUntil).timeIntervalSince1970, 170, accuracy: 0.001)
    }

    func testCategoryRuleTriggersThroughCustomCategoryMapping() throws {
        try CategoryMappingStore.upsert(appName: "com.valvesoftware.steam", category: "Games")
        let categoryTarget = try BlockTarget.category("Games")
        let rule = BlockRule(
            target: categoryTarget,
            policy: try BlockPolicy(baseDurationSeconds: 300, multiplier: 2, maxDurationSeconds: 3_600)
        )
        try BlockRuleStore.upsert(rule: rule)

        let processor = AppBlockingEventProcessor(resolver: AppBlockingEventResolver(
            categoryLookup: { try? CategoryMappingStore.category(for: $0) }
        ))
        let decision = try processor.process(session(appIdentifier: "com.valvesoftware.steam", startedAt: 1_000, duration: 30))

        XCTAssertEqual(decision?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(decision?.rule?.id, rule.id)
        XCTAssertEqual(decision?.blockDurationSeconds, 300)
        XCTAssertEqual(decision?.blockedUntil?.timeIntervalSince1970, 1_330)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: categoryTarget)?.strikeCount, 1)
    }

    func testFallbackCategoryLookupIsUsedWhenCustomMappingIsMissing() throws {
        let categoryTarget = try BlockTarget.category("Entertainment")
        let rule = BlockRule(target: categoryTarget)
        try BlockRuleStore.upsert(rule: rule)

        let processor = AppBlockingEventProcessor(resolver: resolver(
            fallbackCategoryLookup: { appIdentifier in
                appIdentifier == "com.google.Chrome" ? "Entertainment" : nil
            }
        ))

        let decision = try processor.process(session(appIdentifier: "com.google.Chrome", startedAt: 200, duration: 5))

        XCTAssertEqual(decision?.rule?.id, rule.id)
        XCTAssertEqual(decision?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: categoryTarget)?.strikeCount, 1)
    }

    func testUnknownCategoryStillAllowsDirectAppRuleMatching() throws {
        let appTarget = try BlockTarget.app("com.apple.Safari")
        let rule = BlockRule(target: appTarget)
        try BlockRuleStore.upsert(rule: rule)

        let processor = AppBlockingEventProcessor(resolver: resolver())
        let decision = try processor.process(session(appIdentifier: "com.apple.Safari", startedAt: 300, duration: 5))

        XCTAssertEqual(decision?.rule?.id, rule.id)
        XCTAssertEqual(decision?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: appTarget)?.strikeCount, 1)
    }

    func testSubThresholdSessionsDoNotCreateStrikes() throws {
        let appTarget = try BlockTarget.app("com.valvesoftware.steam")
        try BlockRuleStore.upsert(rule: BlockRule(target: appTarget))

        let processor = AppBlockingEventProcessor(
            resolver: resolver(categoryLookup: { _ in "Games" }),
            minimumObservedSessionSeconds: 5
        )
        let decision = try processor.process(session(appIdentifier: "com.valvesoftware.steam", startedAt: 100, duration: 2))

        XCTAssertNil(decision)
        XCTAssertNil(try BlockRuleStore.fetchState(for: appTarget))
    }

    func testProtectedAppsAreIgnoredUnlessExplicitlyAllowed() throws {
        let appTarget = try BlockTarget.app("com.bontecou.time.md")
        try BlockRuleStore.upsert(rule: BlockRule(target: appTarget))

        let protectedProcessor = AppBlockingEventProcessor(resolver: resolver(
            protectedAppIdentifiers: ["com.bontecou.time.md"],
            allowProtectedApps: false
        ))
        XCTAssertNil(try protectedProcessor.process(session(appIdentifier: "com.bontecou.time.md", startedAt: 100, duration: 10)))
        XCTAssertNil(try BlockRuleStore.fetchState(for: appTarget))

        let allowedProcessor = AppBlockingEventProcessor(resolver: resolver(
            protectedAppIdentifiers: ["com.bontecou.time.md"],
            allowProtectedApps: true
        ))
        let decision = try allowedProcessor.process(session(appIdentifier: "com.bontecou.time.md", startedAt: 200, duration: 10))
        XCTAssertEqual(decision?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: appTarget)?.strikeCount, 1)
    }

    private func resolver(
        categoryLookup: @escaping @Sendable (String) -> String? = { _ in nil },
        fallbackCategoryLookup: @escaping @Sendable (String) -> String? = { _ in nil },
        protectedAppIdentifiers: Set<String> = [],
        allowProtectedApps: Bool = false
    ) -> AppBlockingEventResolver {
        AppBlockingEventResolver(
            categoryLookup: categoryLookup,
            fallbackCategoryLookup: fallbackCategoryLookup,
            protectedAppIdentifiers: protectedAppIdentifiers,
            allowProtectedApps: allowProtectedApps
        )
    }

    private func session(appIdentifier: String, startedAt: TimeInterval, duration: TimeInterval) -> AppBlockingSession {
        AppBlockingSession(
            appIdentifier: appIdentifier,
            startedAt: Date(timeIntervalSince1970: startedAt),
            durationSeconds: duration
        )
    }
}
