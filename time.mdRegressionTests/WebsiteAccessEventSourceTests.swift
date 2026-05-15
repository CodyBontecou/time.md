import XCTest
@testable import time_md

final class WebsiteAccessEventSourceTests: XCTestCase {
    private var tempDirectory: URL!
    private var highWaterStore: InMemoryWebsiteAccessHighWaterStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdWebsiteAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        XCTAssertEqual(setenv(BlockRuleStore.environmentOverrideKey, tempDirectory.appendingPathComponent("blocking-rules.db").path, 1), 0)
        highWaterStore = InMemoryWebsiteAccessHighWaterStore()
    }

    override func tearDownWithError() throws {
        _ = unsetenv(BlockRuleStore.environmentOverrideKey)
        highWaterStore = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testVisitToConfiguredDomainTriggersPolicyEvent() async throws {
        let redditTarget = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: redditTarget, policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600))
        try BlockRuleStore.upsert(rule: rule)

        let service = FakeBrowsingHistoryService(browsers: [.safari])
        service.visitsByBrowser[.safari] = [visit(url: "https://www.reddit.com/r/swift", domain: "reddit.com", time: 100, browser: .safari)]
        let source = makeSource(service: service, now: 200)

        let decisions = await source.pollOnce()

        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(decisions.first?.rule?.id, rule.id)
        XCTAssertEqual(decisions.first?.blockedUntil?.timeIntervalSince1970, 160)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: redditTarget)?.strikeCount, 1)
    }

    func testSubdomainVisitIncludesParentDomainForRuleMatching() async throws {
        let redditTarget = try BlockTarget.domain("reddit.com")
        try BlockRuleStore.upsert(rule: BlockRule(target: redditTarget))

        let service = FakeBrowsingHistoryService(browsers: [.chrome])
        service.visitsByBrowser[.chrome] = [visit(url: "https://old.reddit.com/r/macapps", domain: "old.reddit.com", time: 100, browser: .chrome)]
        let source = makeSource(service: service, now: 200)

        let decisions = await source.pollOnce()

        XCTAssertEqual(decisions.first?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(decisions.first?.rule?.target.value, "reddit.com")
        XCTAssertEqual(try BlockRuleStore.fetchState(for: redditTarget)?.strikeCount, 1)
    }

    func testRepeatedPollingDoesNotDoubleCountProcessedVisits() async throws {
        let target = try BlockTarget.domain("reddit.com")
        try BlockRuleStore.upsert(rule: BlockRule(target: target, policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600)))

        let service = FakeBrowsingHistoryService(browsers: [.safari])
        service.visitsByBrowser[.safari] = [visit(url: "https://reddit.com", domain: "reddit.com", time: 100, browser: .safari)]
        let source = makeSource(service: service, now: 200)

        let first = await source.pollOnce()
        let second = await source.pollOnce()

        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: target)?.strikeCount, 1)
        XCTAssertEqual(highWaterStore.highWater(for: .safari)?.timeIntervalSince1970, 100)
    }

    func testDuplicateVisitsAcrossBrowsersAreProcessedOncePerPoll() async throws {
        let target = try BlockTarget.domain("reddit.com")
        try BlockRuleStore.upsert(rule: BlockRule(target: target, policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600)))

        let duplicateTime: TimeInterval = 100
        let service = FakeBrowsingHistoryService(browsers: [.chrome, .arc])
        service.visitsByBrowser[.chrome] = [visit(url: "https://reddit.com/r/apple", domain: "reddit.com", time: duplicateTime, browser: .chrome)]
        service.visitsByBrowser[.arc] = [visit(url: "https://reddit.com/r/apple", domain: "reddit.com", time: duplicateTime, browser: .arc)]
        let source = makeSource(service: service, now: 200)

        let decisions = await source.pollOnce()

        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: target)?.strikeCount, 1)
        XCTAssertEqual(highWaterStore.highWater(for: .chrome)?.timeIntervalSince1970, duplicateTime)
        XCTAssertEqual(highWaterStore.highWater(for: .arc)?.timeIntervalSince1970, duplicateTime)
    }

    func testInvalidUrlsAndLocalhostAreIgnored() async throws {
        try BlockRuleStore.upsert(rule: BlockRule(target: try .domain("reddit.com")))
        let service = FakeBrowsingHistoryService(browsers: [.safari])
        service.visitsByBrowser[.safari] = [
            visit(url: "about:blank", domain: "", time: 100, browser: .safari),
            visit(url: "http://localhost:3000", domain: "localhost", time: 101, browser: .safari),
            visit(url: "file:///tmp/index.html", domain: "", time: 102, browser: .safari),
        ]
        let source = makeSource(service: service, now: 200)

        let decisions = await source.pollOnce()

        XCTAssertTrue(decisions.isEmpty)
        XCTAssertTrue(try BlockRuleStore.fetchStates().isEmpty)
        XCTAssertEqual(highWaterStore.highWater(for: .safari)?.timeIntervalSince1970, 102)
    }

    func testBrowserReadErrorsAreSkippedWithoutThrowing() async throws {
        let target = try BlockTarget.domain("reddit.com")
        try BlockRuleStore.upsert(rule: BlockRule(target: target))

        let service = FakeBrowsingHistoryService(browsers: [.safari, .chrome])
        service.visitsByBrowser[.safari] = [visit(url: "https://reddit.com", domain: "reddit.com", time: 100, browser: .safari)]
        service.errorsByBrowser[.chrome] = BrowsingHistoryError.databaseNotFound(browser: "Chrome")
        let source = makeSource(service: service, now: 200)

        let decisions = await source.pollOnce()

        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: target)?.strikeCount, 1)
        XCTAssertNil(highWaterStore.highWater(for: .chrome))
    }

    func testBrowserHistoryClearDoesNotBreakFutureProcessing() async throws {
        let target = try BlockTarget.domain("reddit.com")
        try BlockRuleStore.upsert(rule: BlockRule(target: target, policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600)))

        let service = FakeBrowsingHistoryService(browsers: [.safari])
        service.visitsByBrowser[.safari] = [visit(url: "https://reddit.com", domain: "reddit.com", time: 100, browser: .safari)]
        let source = makeSource(service: service, now: 200)
        _ = await source.pollOnce()

        service.visitsByBrowser[.safari] = []
        let emptyPoll = await source.pollOnce()
        XCTAssertTrue(emptyPoll.isEmpty)
        XCTAssertEqual(highWaterStore.highWater(for: .safari)?.timeIntervalSince1970, 100)

        service.visitsByBrowser[.safari] = [visit(url: "https://reddit.com/new", domain: "reddit.com", time: 161, browser: .safari)]
        let decisions = await source.pollOnce()

        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(try BlockRuleStore.fetchState(for: target)?.strikeCount, 2)
        XCTAssertEqual(highWaterStore.highWater(for: .safari)?.timeIntervalSince1970, 161)
    }

    func testActiveDomainBlockAttemptDoesNotShortenBlock() async throws {
        let target = try BlockTarget.domain("reddit.com")
        try BlockRuleStore.upsert(rule: BlockRule(target: target, policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600)))

        let service = FakeBrowsingHistoryService(browsers: [.safari])
        service.visitsByBrowser[.safari] = [visit(url: "https://reddit.com", domain: "reddit.com", time: 100, browser: .safari)]
        let source = makeSource(service: service, now: 200)
        _ = await source.pollOnce()

        service.visitsByBrowser[.safari] = [visit(url: "https://reddit.com/again", domain: "reddit.com", time: 120, browser: .safari)]
        let denied = await source.pollOnce()

        XCTAssertEqual(denied.first?.kind, .deniedActiveBlock)
        let state = try XCTUnwrap(BlockRuleStore.fetchState(for: target))
        XCTAssertEqual(state.strikeCount, 1)
        XCTAssertEqual(try XCTUnwrap(state.blockedUntil).timeIntervalSince1970, 160, accuracy: 0.001)
    }

    func testDomainNetworkDecisionReconcilesHelperImmediately() async throws {
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(
            target: target,
            policy: try BlockPolicy(baseDurationSeconds: 60, multiplier: 2, maxDurationSeconds: 600),
            enforcementMode: .domainNetwork
        )
        try BlockRuleStore.upsert(rule: rule)

        let reconciler = FakeWebsiteDomainBlockReconciler()
        let service = FakeBrowsingHistoryService(browsers: [.safari])
        service.visitsByBrowser[.safari] = [visit(url: "https://reddit.com", domain: "reddit.com", time: 100, browser: .safari)]
        let source = makeSource(service: service, now: 200, domainReconcilerFactory: { reconciler })

        let decisions = await source.pollOnce()

        let reconcileCount = await reconciler.reconcileCount
        let lastNow = await reconciler.lastNow
        XCTAssertEqual(decisions.first?.kind, .allowedAndStartedCooldown)
        XCTAssertEqual(reconcileCount, 1)
        XCTAssertEqual(lastNow?.timeIntervalSince1970, 200)
    }

    private func makeSource(
        service: FakeBrowsingHistoryService,
        now timestamp: TimeInterval,
        domainReconcilerFactory: (@Sendable () -> (any WebsiteDomainBlockReconciling)?)? = nil
    ) -> WebsiteAccessEventSource {
        WebsiteAccessEventSource(
            historyService: service,
            highWaterStore: highWaterStore,
            domainReconcilerFactory: domainReconcilerFactory,
            now: { Date(timeIntervalSince1970: timestamp) },
            lookbackInterval: 300,
            fetchLimit: 100,
            pollInterval: 60
        )
    }

    private func visit(url: String, domain: String, time: TimeInterval, browser: BrowserSource) -> BrowsingVisit {
        BrowsingVisit(
            id: "\(browser.rawValue)-\(time)-\(url)",
            url: url,
            title: "",
            domain: domain,
            visitTime: Date(timeIntervalSince1970: time),
            durationSeconds: nil,
            browser: browser
        )
    }
}

private actor FakeWebsiteDomainBlockReconciler: WebsiteDomainBlockReconciling {
    private(set) var reconcileCount = 0
    private(set) var lastNow: Date?

    func reconcileActiveDomainBlocks(now: Date) async throws -> DomainBlockHelperApplyResult {
        reconcileCount += 1
        lastNow = now
        return DomainBlockHelperApplyResult(
            status: DomainBlockHelperStatus(
                installState: .installed,
                helperVersion: nil,
                appVersion: nil,
                activeDomains: ["reddit.com"],
                lastAppliedAt: now,
                lastErrorDescription: nil
            ),
            changedHosts: true,
            changedPFAnchor: true,
            commandOutput: []
        )
    }
}

private final class FakeBrowsingHistoryService: BrowsingHistoryServing, @unchecked Sendable {
    var visitsByBrowser: [BrowserSource: [BrowsingVisit]] = [:]
    var errorsByBrowser: [BrowserSource: Error] = [:]
    private let browsers: [BrowserSource]

    init(browsers: [BrowserSource]) {
        self.browsers = browsers
    }

    func fetchVisits(
        browser: BrowserSource,
        startDate: Date,
        endDate: Date,
        searchText: String,
        limit: Int
    ) async throws -> [BrowsingVisit] {
        if let error = errorsByBrowser[browser] {
            throw error
        }
        return Array((visitsByBrowser[browser] ?? [])
            .filter { $0.visitTime >= startDate && $0.visitTime <= endDate }
            .sorted { $0.visitTime > $1.visitTime }
            .prefix(limit))
    }

    func fetchTopDomains(browser: BrowserSource, startDate: Date, endDate: Date, limit: Int) async throws -> [DomainSummary] { [] }
    func fetchDailyVisitCounts(browser: BrowserSource, startDate: Date, endDate: Date) async throws -> [DailyVisitCount] { [] }
    func fetchHourlyVisitCounts(browser: BrowserSource, startDate: Date, endDate: Date) async throws -> [HourlyVisitCount] { [] }
    func fetchPagesForDomain(domain: String, browser: BrowserSource, startDate: Date, endDate: Date, limit: Int) async throws -> [PageSummary] { [] }
    func availableBrowsers() -> [BrowserSource] { browsers.count > 1 ? [.all] + browsers : browsers }
}
