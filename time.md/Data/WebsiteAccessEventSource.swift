import Foundation

protocol WebsiteAccessHighWaterStoring: Sendable {
    func highWater(for browser: BrowserSource) -> Date?
    func setHighWater(_ date: Date, for browser: BrowserSource)
    func reset()
}

final class InMemoryWebsiteAccessHighWaterStore: WebsiteAccessHighWaterStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BrowserSource: Date] = [:]

    func highWater(for browser: BrowserSource) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return values[browser]
    }

    func setHighWater(_ date: Date, for browser: BrowserSource) {
        lock.lock()
        defer { lock.unlock() }
        values[browser] = date
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}

final class UserDefaultsWebsiteAccessHighWaterStore: WebsiteAccessHighWaterStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix = "websiteAccessHighWater"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func highWater(for browser: BrowserSource) -> Date? {
        let timestamp = defaults.double(forKey: key(for: browser))
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func setHighWater(_ date: Date, for browser: BrowserSource) {
        defaults.set(date.timeIntervalSince1970, forKey: key(for: browser))
    }

    func reset() {
        for browser in BrowserSource.allCases where browser != .all {
            defaults.removeObject(forKey: key(for: browser))
        }
    }

    private func key(for browser: BrowserSource) -> String {
        "\(keyPrefix).\(browser.rawValue)"
    }
}

struct WebsiteAccessDeduplicator: Sendable {
    static let shared = WebsiteAccessDeduplicator(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

    private static let lock = NSLock()
    private static var seenByID: [UUID: [String: Date]] = [:]

    private let id: UUID
    private let windowSeconds: TimeInterval
    private let maximumEntries: Int

    init(windowSeconds: TimeInterval = 10, maximumEntries: Int = 1_000) {
        self.init(id: UUID(), windowSeconds: windowSeconds, maximumEntries: maximumEntries)
    }

    private init(id: UUID, windowSeconds: TimeInterval = 10, maximumEntries: Int = 1_000) {
        self.id = id
        self.windowSeconds = windowSeconds
        self.maximumEntries = maximumEntries
    }

    func shouldProcess(domain: String, url: String, occurredAt: Date, source: String) -> Bool {
        let key = key(domain: domain, url: url)
        Self.lock.lock()
        defer { Self.lock.unlock() }

        var seen = Self.seenByID[id, default: [:]]
        seen = prune(seen, relativeTo: occurredAt)
        if let previous = seen[key], abs(occurredAt.timeIntervalSince(previous)) <= windowSeconds {
            Self.seenByID[id] = seen
            return false
        }
        seen[key] = occurredAt
        if seen.count > maximumEntries { seen = pruneOldest(seen) }
        Self.seenByID[id] = seen
        return true
    }

    func reset() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        Self.seenByID[id] = [:]
    }

    private func key(domain: String, url: String) -> String {
        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(domain.lowercased())|\(normalizedURL)"
    }

    private func prune(_ seen: [String: Date], relativeTo date: Date) -> [String: Date] {
        seen.filter { _, seenDate in
            abs(date.timeIntervalSince(seenDate)) <= windowSeconds
        }
    }

    private func pruneOldest(_ seen: [String: Date]) -> [String: Date] {
        let overflow = seen.count - maximumEntries
        guard overflow > 0 else { return seen }
        var copy = seen
        for key in copy.sorted(by: { $0.value < $1.value }).prefix(overflow).map(\.key) {
            copy.removeValue(forKey: key)
        }
        return copy
    }
}

struct WebsiteAccessEventResolver: Sendable {
    func accessEvents(for visit: BrowsingVisit) -> [BlockAccessEvent] {
        guard let primaryTarget = try? BlockTarget.domain(!visit.url.isEmpty ? visit.url : visit.domain) else {
            return []
        }

        let relatedTargets = suffixDomainTargets(for: primaryTarget.value)
            .filter { $0 != primaryTarget }

        return [BlockAccessEvent(
            target: primaryTarget,
            relatedTargets: relatedTargets,
            occurredAt: visit.visitTime,
            observedDurationSeconds: visit.durationSeconds
        )]
    }

    private func suffixDomainTargets(for normalizedDomain: String) -> [BlockTarget] {
        let labels = normalizedDomain.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return [] }

        var targets: [BlockTarget] = []
        var seen = Set<String>()
        for index in 1..<(labels.count - 1) {
            let candidate = labels[index...].joined(separator: ".")
            guard !seen.contains(candidate), let target = try? BlockTarget.domain(candidate) else { continue }
            seen.insert(candidate)
            targets.append(target)
        }
        return targets
    }
}

protocol WebsiteDomainBlockReconciling: Sendable {
    @discardableResult
    func reconcileActiveDomainBlocks(now: Date) async throws -> DomainBlockHelperApplyResult
}

extension DomainBlockEnforcer: WebsiteDomainBlockReconciling {}

/// Polls local browser history for new visits and feeds normalized domain
/// access events into `BlockPolicyEngine`. This is deliberately independent of
/// web history analytics persistence: browser read failures are logged and
/// skipped so a locked/missing/corrupt browser DB does not break the app.
final class WebsiteAccessEventSource: @unchecked Sendable {
    static let shared = WebsiteAccessEventSource(deduplicator: .shared)
    static let enabledKey = "websiteAccessBlockingEventsEnabled"

    private let historyService: any BrowsingHistoryServing
    private let highWaterStore: any WebsiteAccessHighWaterStoring
    private let resolver: WebsiteAccessEventResolver
    private let engineFactory: @Sendable () -> BlockPolicyEngine
    private let domainReconcilerFactory: (@Sendable () -> (any WebsiteDomainBlockReconciling)?)?
    private let deduplicator: WebsiteAccessDeduplicator
    private let now: @Sendable () -> Date
    private let lookbackInterval: TimeInterval
    private let fetchLimit: Int
    private let pollInterval: TimeInterval

    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var isPolling = false

    init(
        historyService: any BrowsingHistoryServing = SQLiteBrowsingHistoryService(),
        highWaterStore: any WebsiteAccessHighWaterStoring = UserDefaultsWebsiteAccessHighWaterStore(),
        resolver: WebsiteAccessEventResolver = WebsiteAccessEventResolver(),
        engineFactory: @escaping @Sendable () -> BlockPolicyEngine = { BlockPolicyEngine() },
        domainReconcilerFactory: (@Sendable () -> (any WebsiteDomainBlockReconciling)?)? = {
            DomainBlockEnforcer(helper: PrivilegedDomainBlockHelperClient.shared)
        },
        deduplicator: WebsiteAccessDeduplicator = WebsiteAccessDeduplicator(),
        now: @escaping @Sendable () -> Date = { Date() },
        lookbackInterval: TimeInterval = 5 * 60,
        fetchLimit: Int = 250,
        pollInterval: TimeInterval = 15
    ) {
        self.historyService = historyService
        self.highWaterStore = highWaterStore
        self.resolver = resolver
        self.engineFactory = engineFactory
        self.domainReconcilerFactory = domainReconcilerFactory
        self.deduplicator = deduplicator
        self.now = now
        self.lookbackInterval = lookbackInterval
        self.fetchLimit = fetchLimit
        self.pollInterval = pollInterval
    }

    static var isEnabled: Bool {
        if let value = UserDefaults.standard.object(forKey: enabledKey) as? Bool {
            return value
        }
        return true
    }

    func start(browser: BrowserSource = .all) {
        guard Self.isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            Task { _ = await self?.pollOnce(browser: browser) }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
    }

    @discardableResult
    func pollOnce(browser: BrowserSource = .all) async -> [BlockPolicyDecision] {
        guard Self.isEnabled else { return [] }
        if !beginPolling() { return [] }
        defer { endPolling() }

        let browsers = browsersToPoll(browser)
        var decisions: [BlockPolicyDecision] = []
        var processedVisitKeys = Set<String>()

        for browser in browsers {
            let previousHighWater = highWaterStore.highWater(for: browser)
            let startDate = previousHighWater ?? now().addingTimeInterval(-lookbackInterval)
            let endDate = now()
            let visits: [BrowsingVisit]

            do {
                visits = try await historyService.fetchVisits(
                    browser: browser,
                    startDate: startDate,
                    endDate: endDate,
                    searchText: "",
                    limit: fetchLimit
                )
            } catch {
                NSLog("[WebsiteAccessEventSource] Failed to read \(browser.displayName) history: \(error.localizedDescription)")
                continue
            }

            let sortedVisits = visits.sorted { lhs, rhs in
                if lhs.visitTime != rhs.visitTime { return lhs.visitTime < rhs.visitTime }
                return lhs.url < rhs.url
            }
            var maxSeen = previousHighWater

            for visit in sortedVisits {
                if let previousHighWater, visit.visitTime <= previousHighWater {
                    continue
                }
                if maxSeen == nil || visit.visitTime > maxSeen! {
                    maxSeen = visit.visitTime
                }

                let visitKey = deduplicationKey(for: visit)
                guard processedVisitKeys.insert(visitKey).inserted else { continue }

                for event in resolver.accessEvents(for: visit) {
                    guard deduplicator.shouldProcess(
                        domain: event.target.value,
                        url: visit.url.isEmpty ? visit.domain : visit.url,
                        occurredAt: event.occurredAt,
                        source: "history.\(browser.rawValue)"
                    ) else { continue }

                    do {
                        decisions.append(try engineFactory().handleAccess(event))
                    } catch {
                        NSLog("[WebsiteAccessEventSource] Failed to process website access event: \(error.localizedDescription)")
                    }
                }
            }

            if let maxSeen, maxSeen != previousHighWater {
                highWaterStore.setHighWater(maxSeen, for: browser)
            }
        }

        await reconcileDomainBlocksIfNeeded(for: decisions, now: now())
        return decisions
    }

    private func reconcileDomainBlocksIfNeeded(for decisions: [BlockPolicyDecision], now: Date) async {
        let needsDomainReconcile = decisions.contains { decision in
            guard let rule = decision.rule else { return false }
            return rule.enabled
                && rule.target.type == .domain
                && rule.enforcementMode == .domainNetwork
                && (decision.kind == .allowedAndStartedCooldown || decision.kind == .deniedActiveBlock)
        }
        guard needsDomainReconcile, let reconciler = domainReconcilerFactory?() else { return }

        do {
            _ = try await reconciler.reconcileActiveDomainBlocks(now: now)
        } catch {
            NSLog("[WebsiteAccessEventSource] Failed to reconcile domain blocks: \(error.localizedDescription)")
        }
    }

    private func browsersToPoll(_ browser: BrowserSource) -> [BrowserSource] {
        if browser != .all { return [browser] }
        return historyService.availableBrowsers().filter { $0 != .all }
    }

    private func deduplicationKey(for visit: BrowsingVisit) -> String {
        let normalizedTarget = try? BlockTarget.domain(!visit.url.isEmpty ? visit.url : visit.domain)
        let domain = normalizedTarget?.value ?? visit.domain.lowercased()
        let timestamp = Int64((visit.visitTime.timeIntervalSince1970 * 1_000).rounded())
        return "\(domain)|\(timestamp)|\(visit.url.lowercased())"
    }

    private func beginPolling() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isPolling else { return false }
        isPolling = true
        return true
    }

    private func endPolling() {
        lock.lock()
        defer { lock.unlock() }
        isPolling = false
    }
}
