import XCTest
@testable import time_md

final class AppBlockEnforcerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdAppBlockEnforcerTests-\(UUID().uuidString)", isDirectory: true)
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

    func testDirectAppBlockShowsCountdownAndHidesApp() async throws {
        let target = try BlockTarget.app("com.example.Game")
        let rule = BlockRule(target: target, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: target,
            ruleID: rule.id,
            strikeCount: 1,
            blockedUntil: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 100)
        ))

        let controller = RecordingAppBlockController()
        let presenter = RecordingAppBlockPresenter()
        let enforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in nil }),
            controller: controller,
            presenter: presenter,
            protectedAppIdentifiers: [],
            now: { Date(timeIntervalSince1970: 150) }
        )

        let optionalResult = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.example.Game", displayName: "Game"))
        let result = try XCTUnwrap(optionalResult)
        XCTAssertEqual(result.match.kind, .app)
        XCTAssertEqual(result.action, .showCountdownAndHide)
        XCTAssertTrue(result.didPerformAction)
        let hidden = await controller.hiddenIdentifiers()
        let activateCount = await controller.activateCountValue()
        let notices = await presenter.noticeIdentifiers()
        XCTAssertEqual(hidden, ["com.example.Game"])
        XCTAssertEqual(activateCount, 1)
        XCTAssertEqual(notices, ["com.example.Game"])
    }

    func testCategoryBlockMatchesCurrentCategoryMapping() async throws {
        let categoryTarget = try BlockTarget.category("Games")
        let rule = BlockRule(target: categoryTarget, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: categoryTarget,
            ruleID: rule.id,
            strikeCount: 1,
            blockedUntil: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 100)
        ))

        let controller = RecordingAppBlockController()
        let enforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { app in app == "com.example.Game" ? "Games" : nil }),
            controller: controller,
            protectedAppIdentifiers: [],
            now: { Date(timeIntervalSince1970: 150) }
        )

        let optionalResult = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.example.Game"))
        let result = try XCTUnwrap(optionalResult)
        XCTAssertEqual(result.match.kind, .category)
        XCTAssertEqual(result.match.category, "Games")
        let hidden = await controller.hiddenIdentifiers()
        XCTAssertEqual(hidden, ["com.example.Game"])
    }

    func testDirectAppMatchWinsOverBlockedCategory() async throws {
        let appTarget = try BlockTarget.app("com.example.Game")
        let categoryTarget = try BlockTarget.category("Games")
        let appRule = BlockRule(target: appTarget, enforcementMode: .appFocus)
        let categoryRule = BlockRule(target: categoryTarget, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: appRule)
        try BlockRuleStore.upsert(rule: categoryRule)
        try BlockRuleStore.upsert(state: try BlockState(target: categoryTarget, ruleID: categoryRule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 300), updatedAt: Date(timeIntervalSince1970: 100)))
        try BlockRuleStore.upsert(state: try BlockState(target: appTarget, ruleID: appRule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 100)))

        let enforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in "Games" }),
            protectedAppIdentifiers: [],
            now: { Date(timeIntervalSince1970: 150) }
        )

        let optionalResult = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.example.Game"))
        let result = try XCTUnwrap(optionalResult)
        XCTAssertEqual(result.match.kind, .app)
        XCTAssertEqual(result.match.target, appTarget)
    }

    func testProtectedAppsAreSkippedByDefaultUnlessExplicitlyAllowed() async throws {
        let target = try BlockTarget.app("com.apple.finder")
        let rule = BlockRule(target: target, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(target: target, ruleID: rule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 100)))

        let protectedController = RecordingAppBlockController()
        let protectedEnforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in nil }),
            controller: protectedController,
            protectedAppIdentifiers: ["com.apple.finder"],
            now: { Date(timeIntervalSince1970: 150) }
        )
        let protectedResult = await protectedEnforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.apple.finder", displayName: "Finder"))
        let protectedHidden = await protectedController.hiddenIdentifiers()
        XCTAssertNil(protectedResult)
        XCTAssertEqual(protectedHidden, [])

        let allowedController = RecordingAppBlockController()
        let allowedEnforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in nil }),
            controller: allowedController,
            allowProtectedApps: true,
            protectedAppIdentifiers: ["com.apple.finder"],
            now: { Date(timeIntervalSince1970: 150) }
        )
        let allowedResult = await allowedEnforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.apple.finder", displayName: "Finder"))
        let allowedHidden = await allowedController.hiddenIdentifiers()
        XCTAssertNotNil(allowedResult)
        XCTAssertEqual(allowedHidden, ["com.apple.finder"])
    }

    func testExpiredBlocksAreClearedAndNotEnforced() async throws {
        let target = try BlockTarget.app("com.example.Game")
        let rule = BlockRule(target: target, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(target: target, ruleID: rule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 120), updatedAt: Date(timeIntervalSince1970: 100)))

        let controller = RecordingAppBlockController()
        let enforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in nil }),
            controller: controller,
            protectedAppIdentifiers: [],
            now: { Date(timeIntervalSince1970: 150) }
        )

        let result = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.example.Game"))
        let hidden = await controller.hiddenIdentifiers()
        XCTAssertNil(result)
        XCTAssertEqual(hidden, [])
        XCTAssertNil(try BlockRuleStore.fetchState(for: target)?.blockedUntil)
    }

    func testRepeatedActivationIsThrottledToAvoidActionSpam() async throws {
        let target = try BlockTarget.app("com.example.Game")
        let rule = BlockRule(target: target, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(target: target, ruleID: rule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 300), updatedAt: Date(timeIntervalSince1970: 100)))

        let clock = LockedTestClock(Date(timeIntervalSince1970: 150))
        let controller = RecordingAppBlockController()
        let enforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in nil }),
            controller: controller,
            protectedAppIdentifiers: [],
            throttleInterval: 10,
            now: { clock.now }
        )

        let firstOptional = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.example.Game"))
        let first = try XCTUnwrap(firstOptional)
        XCTAssertFalse(first.wasThrottled)

        clock.now = Date(timeIntervalSince1970: 155)
        let secondOptional = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.example.Game"))
        let second = try XCTUnwrap(secondOptional)
        XCTAssertTrue(second.wasThrottled)
        XCTAssertFalse(second.didPerformAction)
        let hidden = await controller.hiddenIdentifiers()
        XCTAssertEqual(hidden, ["com.example.Game"])
    }

    func testEnforcementActionsAreAudited() async throws {
        let target = try BlockTarget.app("com.example.Game")
        let rule = BlockRule(target: target, enforcementMode: .appFocus)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(target: target, ruleID: rule.id, strikeCount: 1, blockedUntil: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 100)))

        let controller = RecordingAppBlockController()
        let enforcer = AppBlockEnforcer(
            categoryResolver: AppBlockCategoryResolver(categoryForApp: { _ in nil }),
            controller: controller,
            protectedAppIdentifiers: [],
            now: { Date(timeIntervalSince1970: 150) }
        )

        let optionalResult = await enforcer.enforceIfNeeded(for: AppBlockCandidate(identifier: "com.example.Game"))
        let result = try XCTUnwrap(optionalResult)
        XCTAssertTrue(result.didPerformAction)
        let audit = try XCTUnwrap(BlockRuleStore.fetchAuditEvents(limit: 5).first { $0.message == "App block enforcement applied" })
        XCTAssertEqual(audit.metadata["appIdentifier"], "com.example.Game")
        XCTAssertEqual(audit.metadata["didPerformAction"], "true")
    }
}

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

private actor RecordingAppBlockController: AppBlockControlling {
    private var hidden: [String] = []
    private var terminated: [String] = []
    private var activateCount = 0
    private let hideResult: Bool

    init(hideResult: Bool = true) {
        self.hideResult = hideResult
    }

    func hide(_ app: AppBlockCandidate) async throws -> Bool {
        hidden.append(app.identifier)
        return hideResult
    }

    func terminate(_ app: AppBlockCandidate) async throws -> Bool {
        terminated.append(app.identifier)
        return true
    }

    func activateBlockerApp() async {
        activateCount += 1
    }

    func hiddenIdentifiers() -> [String] { hidden }
    func terminatedIdentifiers() -> [String] { terminated }
    func activateCountValue() -> Int { activateCount }
}

private actor RecordingAppBlockPresenter: AppBlockNoticePresenting {
    private var notices: [(app: AppBlockCandidate, match: AppBlockMatch, blockedUntil: Date, action: AppBlockEnforcementAction)] = []

    func showBlockNotice(for app: AppBlockCandidate, match: AppBlockMatch, until blockedUntil: Date, action: AppBlockEnforcementAction) async {
        notices.append((app, match, blockedUntil, action))
    }

    func noticeIdentifiers() -> [String] {
        notices.map(\.app.identifier)
    }
}
