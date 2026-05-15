import XCTest
@testable import time_md

final class BrowserExtensionBridgeTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdBrowserExtensionBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        XCTAssertEqual(setenv(BlockRuleStore.environmentOverrideKey, tempDirectory.appendingPathComponent("blocking-rules.db").path, 1), 0)
    }

    override func tearDownWithError() throws {
        _ = unsetenv(BlockRuleStore.environmentOverrideKey)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testParsesURLAccessPayloadAndTriggersDomainRule() throws {
        let now = Date(timeIntervalSince1970: 100)
        let rule = BlockRule(target: try .domain("reddit.com"), enforcementMode: .domainNetwork)
        try BlockRuleStore.upsert(rule: rule)

        let bridge = BrowserExtensionBridge(deduplicator: WebsiteAccessDeduplicator(), now: { now })
        let payload = jsonData([
            "type": "urlAccess",
            "url": "https://www.reddit.com/r/swift",
            "title": "Swift",
            "browser": "Chrome",
            "tabId": 42,
            "occurredAt": 100
        ])

        let message = try bridge.parseURLAccessMessage(payload)
        XCTAssertEqual(message.tabID, 42)

        let response = bridge.handleJSONMessage(payload, source: "extension.chrome")
        XCTAssertEqual(response.action, .allow)
        XCTAssertEqual(response.targetDomain, "reddit.com")
        XCTAssertEqual(response.remainingSeconds, 60)

        let state = try XCTUnwrap(BlockRuleStore.fetchState(for: rule.target))
        XCTAssertEqual(state.strikeCount, 1)
        XCTAssertEqual(state.blockedUntil, Date(timeIntervalSince1970: 160))
    }

    func testInvalidAndMaliciousMessagesAreIgnoredSafely() throws {
        let bridge = BrowserExtensionBridge(deduplicator: WebsiteAccessDeduplicator(), now: { Date(timeIntervalSince1970: 100) }, maximumMessageBytes: 64)

        XCTAssertEqual(bridge.handleJSONMessage(Data("not-json".utf8)).action, .invalid)
        XCTAssertEqual(bridge.handleJSONMessage(jsonData(["type": "ping", "url": "https://reddit.com"])).action, .invalid)
        XCTAssertEqual(bridge.handleJSONMessage(jsonData(["type": "urlAccess", "url": "javascript:alert(1)"])).action, .invalid)
        XCTAssertEqual(bridge.handleJSONMessage(jsonData(["type": "urlAccess", "url": "file:///etc/hosts"])).action, .invalid)
        XCTAssertEqual(bridge.handleJSONMessage(Data(repeating: 65, count: 65)).action, .invalid)
        XCTAssertTrue(try BlockRuleStore.fetchStates().isEmpty)
    }

    func testActiveBlockResponsePayloadTellsExtensionToBlockWithCountdown() throws {
        let now = Date(timeIntervalSince1970: 100)
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: target, enforcementMode: .domainNetwork)
        try BlockRuleStore.upsert(rule: rule)
        try BlockRuleStore.upsert(state: try BlockState(
            target: target,
            ruleID: rule.id,
            strikeCount: 1,
            blockedUntil: Date(timeIntervalSince1970: 220),
            lastBlockedAt: now,
            updatedAt: now
        ))

        let bridge = BrowserExtensionBridge(deduplicator: WebsiteAccessDeduplicator(), now: { now })
        let response = bridge.handleJSONMessage(jsonData([
            "type": "urlAccess",
            "url": "https://reddit.com/",
            "occurredAt": 110
        ]))

        XCTAssertEqual(response.action, .block)
        XCTAssertEqual(response.targetDomain, "reddit.com")
        XCTAssertEqual(response.blockedUntil, Date(timeIntervalSince1970: 220))
        XCTAssertEqual(response.remainingSeconds, 110)
        XCTAssertTrue(response.reason?.contains("blocked") ?? false)
    }

    func testExtensionAndHistoryEventsShareDeduplicationWindow() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let target = try BlockTarget.domain("reddit.com")
        let rule = BlockRule(target: target, enforcementMode: .domainNetwork)
        try BlockRuleStore.upsert(rule: rule)

        let deduplicator = WebsiteAccessDeduplicator(windowSeconds: 10)
        let bridge = BrowserExtensionBridge(deduplicator: deduplicator, now: { now })
        let extensionResponse = bridge.handleJSONMessage(jsonData([
            "type": "urlAccess",
            "url": "https://reddit.com/r/swift",
            "occurredAt": 100
        ]))
        XCTAssertEqual(extensionResponse.action, .allow)

        let history = FakeBrowsingHistoryService(visits: [
            BrowsingVisit(
                id: "chrome-1",
                url: "https://reddit.com/r/swift",
                title: "Swift",
                domain: "reddit.com",
                visitTime: Date(timeIntervalSince1970: 101),
                durationSeconds: nil,
                browser: .chrome
            )
        ])
        let source = WebsiteAccessEventSource(
            historyService: history,
            highWaterStore: InMemoryWebsiteAccessHighWaterStore(),
            engineFactory: { BlockPolicyEngine() },
            deduplicator: deduplicator,
            now: { Date(timeIntervalSince1970: 105) },
            pollInterval: 60
        )

        let decisions = await source.pollOnce(browser: .chrome)
        XCTAssertTrue(decisions.isEmpty)
        let state = try XCTUnwrap(BlockRuleStore.fetchState(for: target))
        XCTAssertEqual(state.strikeCount, 1)
    }

    func testNativeMessageCodecFramesResponses() throws {
        let response = BrowserExtensionBridgeResponse(
            version: 1,
            action: .block,
            targetDomain: "reddit.com",
            blockedUntil: Date(timeIntervalSince1970: 200),
            remainingSeconds: 100,
            reason: "blocked"
        )

        let framed = try BrowserExtensionNativeMessageCodec.encode(response)
        let payload = try BrowserExtensionNativeMessageCodec.decode(framed)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(BrowserExtensionBridgeResponse.self, from: payload)
        XCTAssertEqual(decoded.action, .block)
        XCTAssertEqual(decoded.targetDomain, "reddit.com")
    }

    private func jsonData(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private final class FakeBrowsingHistoryService: BrowsingHistoryServing, @unchecked Sendable {
    var visits: [BrowsingVisit]

    init(visits: [BrowsingVisit]) {
        self.visits = visits
    }

    func fetchVisits(browser: BrowserSource, startDate: Date, endDate: Date, searchText: String, limit: Int) async throws -> [BrowsingVisit] {
        visits.filter { $0.browser == browser && $0.visitTime >= startDate && $0.visitTime <= endDate }
    }

    func fetchTopDomains(browser: BrowserSource, startDate: Date, endDate: Date, limit: Int) async throws -> [DomainSummary] { [] }
    func fetchDailyVisitCounts(browser: BrowserSource, startDate: Date, endDate: Date) async throws -> [DailyVisitCount] { [] }
    func fetchHourlyVisitCounts(browser: BrowserSource, startDate: Date, endDate: Date) async throws -> [HourlyVisitCount] { [] }
    func fetchPagesForDomain(domain: String, browser: BrowserSource, startDate: Date, endDate: Date, limit: Int) async throws -> [PageSummary] { [] }
    func availableBrowsers() -> [BrowserSource] { [.chrome] }
}
