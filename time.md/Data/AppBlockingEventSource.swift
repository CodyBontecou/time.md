import Foundation

/// Completed foreground-app session emitted by `ActiveAppTracker` for blocking
/// policy evaluation. This is intentionally separate from analytics writes so
/// blocking can be disabled or fail without affecting usage tracking.
struct AppBlockingSession: Sendable {
    let appIdentifier: String
    let startedAt: Date
    let durationSeconds: TimeInterval

    var endedAt: Date {
        startedAt.addingTimeInterval(durationSeconds)
    }
}

/// Resolves app sessions into policy-engine access events. Direct app targets
/// are always emitted; category targets are added when a custom mapping or app
/// metadata category can be resolved.
struct AppBlockingEventResolver: Sendable {
    var categoryLookup: @Sendable (String) -> String?
    var fallbackCategoryLookup: @Sendable (String) -> String?
    var protectedAppIdentifiers: Set<String>
    var allowProtectedApps: Bool

    init(
        categoryLookup: @escaping @Sendable (String) -> String?,
        fallbackCategoryLookup: @escaping @Sendable (String) -> String? = { _ in nil },
        protectedAppIdentifiers: Set<String> = [],
        allowProtectedApps: Bool = false
    ) {
        self.categoryLookup = categoryLookup
        self.fallbackCategoryLookup = fallbackCategoryLookup
        self.protectedAppIdentifiers = protectedAppIdentifiers
        self.allowProtectedApps = allowProtectedApps
    }

    static var live: AppBlockingEventResolver {
        AppBlockingEventResolver(
            categoryLookup: { appIdentifier in
                try? CategoryMappingStore.category(for: appIdentifier)
            },
            fallbackCategoryLookup: { appIdentifier in
                #if canImport(AppKit)
                return AppCategorizer.resolveCategory(for: appIdentifier)
                #else
                return nil
                #endif
            },
            protectedAppIdentifiers: Set([Bundle.main.bundleIdentifier].compactMap { $0 }),
            allowProtectedApps: UserDefaults.standard.bool(forKey: AppBlockingEventDispatcher.allowSelfBlockingKey)
        )
    }

    func accessEvent(for session: AppBlockingSession) throws -> BlockAccessEvent? {
        let trimmedIdentifier = session.appIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else { return nil }

        let appTarget = try BlockTarget.app(trimmedIdentifier)
        if !allowProtectedApps,
           protectedAppIdentifiers.contains(appTarget.value) || protectedAppIdentifiers.contains(trimmedIdentifier) {
            return nil
        }

        let category = categoryLookup(trimmedIdentifier) ?? categoryLookup(appTarget.value) ?? fallbackCategoryLookup(trimmedIdentifier) ?? fallbackCategoryLookup(appTarget.value)
        let categoryTarget = try category.flatMap { try BlockTarget.category($0) }

        return BlockAccessEvent(
            target: appTarget,
            relatedTargets: [categoryTarget].compactMap { $0 },
            occurredAt: session.endedAt,
            observedDurationSeconds: session.durationSeconds
        )
    }
}

/// Synchronous app-session processor used by the live dispatcher and by tests
/// with fake category lookups. It keeps event resolution and policy handoff
/// injectable without requiring `ActiveAppTracker` or AppKit.
struct AppBlockingEventProcessor: Sendable {
    var resolver: AppBlockingEventResolver
    var engine: BlockPolicyEngine
    var minimumObservedSessionSeconds: TimeInterval
    var enabled: Bool

    init(
        resolver: AppBlockingEventResolver,
        engine: BlockPolicyEngine = BlockPolicyEngine(),
        minimumObservedSessionSeconds: TimeInterval = 2.0,
        enabled: Bool = true
    ) {
        self.resolver = resolver
        self.engine = engine
        self.minimumObservedSessionSeconds = minimumObservedSessionSeconds
        self.enabled = enabled
    }

    func process(_ session: AppBlockingSession) throws -> BlockPolicyDecision? {
        guard enabled, session.durationSeconds >= minimumObservedSessionSeconds else { return nil }
        guard let event = try resolver.accessEvent(for: session) else { return nil }
        return try engine.handleAccess(event)
    }
}

/// Bridges completed app sessions into `BlockPolicyEngine`. Failures are logged
/// and intentionally swallowed so analytics tracking continues even if blocking
/// persistence or policy evaluation fails.
final class AppBlockingEventDispatcher: @unchecked Sendable {
    static let shared = AppBlockingEventDispatcher()

    static let enabledKey = "appCategoryBlockingEventsEnabled"
    static let allowSelfBlockingKey = "appCategoryBlockingAllowSelfBlocking"

    /// Mirrors `ActiveAppTracker`'s fly-through filter and gives tests/future UI
    /// one place to adjust app-blocking event sensitivity independently from
    /// analytics session persistence.
    var minimumObservedSessionSeconds: TimeInterval = 2.0

    private let resolverFactory: () -> AppBlockingEventResolver
    private let engineFactory: () -> BlockPolicyEngine

    init(
        resolverFactory: @escaping () -> AppBlockingEventResolver = { .live },
        engineFactory: @escaping () -> BlockPolicyEngine = { BlockPolicyEngine() }
    ) {
        self.resolverFactory = resolverFactory
        self.engineFactory = engineFactory
    }

    static var isEnabled: Bool {
        if let value = UserDefaults.standard.object(forKey: enabledKey) as? Bool {
            return value
        }
        return true
    }

    func recordCompletedSession(appIdentifier: String, startedAt: Date, durationSeconds: TimeInterval) {
        guard Self.isEnabled, durationSeconds >= minimumObservedSessionSeconds else { return }

        let session = AppBlockingSession(
            appIdentifier: appIdentifier,
            startedAt: startedAt,
            durationSeconds: durationSeconds
        )

        let resolver = resolverFactory()
        let engine = engineFactory()
        let minimumObservedSessionSeconds = minimumObservedSessionSeconds

        DispatchQueue.global(qos: .utility).async {
            do {
                let processor = AppBlockingEventProcessor(
                    resolver: resolver,
                    engine: engine,
                    minimumObservedSessionSeconds: minimumObservedSessionSeconds,
                    enabled: true
                )
                _ = try processor.process(session)
            } catch {
                print("[AppBlockingEventDispatcher] Failed to process app blocking event: \(error.localizedDescription)")
            }
        }
    }
}
