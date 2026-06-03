import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct AppBlockCandidate: Codable, Hashable, Sendable {
    var identifier: String
    var displayName: String?
    var processIdentifier: Int32?

    nonisolated init(identifier: String, displayName: String? = nil, processIdentifier: Int32? = nil) {
        self.identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.processIdentifier = processIdentifier
    }
}

enum AppBlockEnforcementAction: String, Codable, CaseIterable, Sendable {
    /// Safest default: explain the block, hide the blocked app, then bring
    /// time.md forward so the user can see the countdown and adjust rules.
    case showCountdownAndHide
    /// Hide the app without foregrounding time.md.
    case hide
    /// Request graceful termination. This can fail and should remain opt-in.
    case terminate
    /// Explain only; useful for dry-runs and accessibility fallback.
    case notifyOnly
}

enum AppBlockMatchKind: String, Codable, Sendable {
    case app
    case category
}

struct AppBlockMatch: Hashable, Sendable {
    var kind: AppBlockMatchKind
    var target: BlockTarget
    var activeBlock: ActiveBlock
    var category: String?
}

struct AppBlockEnforcementResult: Hashable, Sendable {
    var app: AppBlockCandidate
    var match: AppBlockMatch
    var action: AppBlockEnforcementAction
    var enforcedAt: Date
    var blockedUntil: Date
    var didPerformAction: Bool
    var wasThrottled: Bool
    var errorDescription: String?
}

protocol AppBlockControlling: Sendable {
    func hide(_ app: AppBlockCandidate) async throws -> Bool
    func terminate(_ app: AppBlockCandidate) async throws -> Bool
    func activateBlockerApp() async
}

protocol AppBlockNoticePresenting: Sendable {
    func showBlockNotice(for app: AppBlockCandidate, match: AppBlockMatch, until blockedUntil: Date, action: AppBlockEnforcementAction) async
}

struct AppBlockCategoryResolver: Sendable {
    var categoryForApp: @Sendable (String) -> String?
    var fallbackCategoryForApp: @Sendable (String) -> String?

    nonisolated init(
        categoryForApp: @escaping @Sendable (String) -> String?,
        fallbackCategoryForApp: @escaping @Sendable (String) -> String? = { _ in nil }
    ) {
        self.categoryForApp = categoryForApp
        self.fallbackCategoryForApp = fallbackCategoryForApp
    }

    static var live: AppBlockCategoryResolver {
        AppBlockCategoryResolver(
            categoryForApp: { identifier in try? CategoryMappingStore.category(for: identifier) },
            fallbackCategoryForApp: { identifier in
                #if canImport(AppKit)
                return AppCategorizer.resolveCategory(for: identifier)
                #else
                return nil
                #endif
            }
        )
    }

    func category(for app: AppBlockCandidate) -> String? {
        let identifier = app.identifier
        return categoryForApp(identifier)
            ?? app.displayName.flatMap(categoryForApp)
            ?? fallbackCategoryForApp(identifier)
            ?? app.displayName.flatMap(fallbackCategoryForApp)
    }
}

struct NoopAppBlockController: AppBlockControlling {
    nonisolated init() {}
    func hide(_ app: AppBlockCandidate) async throws -> Bool { true }
    func terminate(_ app: AppBlockCandidate) async throws -> Bool { true }
    func activateBlockerApp() async {}
}

struct NoopAppBlockNoticePresenter: AppBlockNoticePresenting {
    nonisolated init() {}
    func showBlockNotice(for app: AppBlockCandidate, match: AppBlockMatch, until blockedUntil: Date, action: AppBlockEnforcementAction) async {}
}

final class AppBlockEnforcer: @unchecked Sendable {
    static let enabledKey = "appCategoryBlockEnforcementEnabled"
    static let actionKey = "appCategoryBlockEnforcementAction"
    static let allowProtectedAppsKey = "appCategoryBlockEnforcementAllowProtectedApps"

    private let engine: BlockPolicyEngine
    private let categoryResolver: AppBlockCategoryResolver
    private let controller: any AppBlockControlling
    private let presenter: any AppBlockNoticePresenting
    private let now: @Sendable () -> Date
    private let protectedAppIdentifiers: Set<String>
    private let throttleInterval: TimeInterval
    private let shouldLogAuditEvents: Bool
    private let lock = NSLock()
    private var lastActionByAppIdentifier: [String: Date] = [:]

    var action: AppBlockEnforcementAction
    var allowProtectedApps: Bool
    var enabled: Bool

    nonisolated static var liveAction: AppBlockEnforcementAction {
        if let raw = UserDefaults.standard.string(forKey: actionKey),
           let action = AppBlockEnforcementAction(rawValue: raw) {
            return action
        }
        return .showCountdownAndHide
    }

    nonisolated static var isLiveEnabled: Bool {
        if let value = UserDefaults.standard.object(forKey: enabledKey) as? Bool { return value }
        return true
    }

    nonisolated static var defaultProtectedAppIdentifiers: Set<String> {
        var identifiers: Set<String> = [
            "com.apple.finder",
            "com.apple.systempreferences",
            "com.apple.SystemSettings",
            "com.apple.Terminal",
            "com.apple.loginwindow",
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.ActivityMonitor"
        ]
        if let selfIdentifier = Bundle.main.bundleIdentifier {
            identifiers.insert(selfIdentifier)
        }
        return identifiers
    }

    static var live: AppBlockEnforcer {
        AppBlockEnforcer(
            engine: BlockPolicyEngine(),
            categoryResolver: .live,
            controller: LiveAppBlockController(),
            presenter: AppBlockNoticeWindowPresenter.shared,
            action: liveAction,
            allowProtectedApps: UserDefaults.standard.bool(forKey: allowProtectedAppsKey),
            enabled: isLiveEnabled,
            protectedAppIdentifiers: defaultProtectedAppIdentifiers
        )
    }

    init(
        engine: BlockPolicyEngine = BlockPolicyEngine(),
        categoryResolver: AppBlockCategoryResolver,
        controller: any AppBlockControlling = NoopAppBlockController(),
        presenter: any AppBlockNoticePresenting = NoopAppBlockNoticePresenter(),
        action: AppBlockEnforcementAction = .showCountdownAndHide,
        allowProtectedApps: Bool = false,
        enabled: Bool = true,
        protectedAppIdentifiers: Set<String> = AppBlockEnforcer.defaultProtectedAppIdentifiers,
        throttleInterval: TimeInterval = 5,
        shouldLogAuditEvents: Bool = true,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.engine = engine
        self.categoryResolver = categoryResolver
        self.controller = controller
        self.presenter = presenter
        self.action = action
        self.allowProtectedApps = allowProtectedApps
        self.enabled = enabled
        self.protectedAppIdentifiers = protectedAppIdentifiers
        self.throttleInterval = throttleInterval
        self.shouldLogAuditEvents = shouldLogAuditEvents
        self.now = now
    }

    @discardableResult
    func enforceIfNeeded(for app: AppBlockCandidate) async -> AppBlockEnforcementResult? {
        guard enabled, !app.identifier.isEmpty else { return nil }
        let currentTime = now()
        guard allowProtectedApps || !isProtected(app) else { return nil }

        do {
            _ = try engine.clearExpiredBlocks(now: currentTime)
            let activeBlocks = try engine.activeBlocks(now: currentTime)
            guard let match = try match(for: app, activeBlocks: activeBlocks) else { return nil }

            if let lastAction = lastActionDate(for: app.identifier),
               currentTime.timeIntervalSince(lastAction) < throttleInterval {
                return AppBlockEnforcementResult(
                    app: app,
                    match: match,
                    action: action,
                    enforcedAt: currentTime,
                    blockedUntil: match.activeBlock.effectiveBlockedUntil,
                    didPerformAction: false,
                    wasThrottled: true,
                    errorDescription: nil
                )
            }

            await presenter.showBlockNotice(for: app, match: match, until: match.activeBlock.effectiveBlockedUntil, action: action)

            var didPerformAction = false
            var errorDescription: String?
            do {
                didPerformAction = try await performConfiguredAction(action, for: app)
            } catch {
                errorDescription = error.localizedDescription
            }

            setLastActionDate(currentTime, for: app.identifier)
            let result = AppBlockEnforcementResult(
                app: app,
                match: match,
                action: action,
                enforcedAt: currentTime,
                blockedUntil: match.activeBlock.effectiveBlockedUntil,
                didPerformAction: didPerformAction,
                wasThrottled: false,
                errorDescription: errorDescription
            )
            if shouldLogAuditEvents {
                try? logAuditEvent(result)
            }
            return result
        } catch {
            NSLog("[AppBlockEnforcer] Failed to evaluate app block for \(app.identifier): \(error.localizedDescription)")
            return nil
        }
    }

    private func lastActionDate(for identifier: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastActionByAppIdentifier[identifier]
    }

    private func setLastActionDate(_ date: Date, for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        lastActionByAppIdentifier[identifier] = date
    }

    private func match(for app: AppBlockCandidate, activeBlocks: [ActiveBlock]) throws -> AppBlockMatch? {
        let appTarget = try BlockTarget.app(app.identifier)
        let category = categoryResolver.category(for: app)
        let categoryTarget = try category.flatMap { try BlockTarget.category($0) }

        let appMatch = activeBlocks.first { block in
            guard block.state.target.type == .app else { return false }
            guard block.rule?.enforcementMode != .monitorOnly else { return false }
            return block.state.target == appTarget || block.state.target.value == app.identifier
        }
        if let appMatch {
            return AppBlockMatch(kind: .app, target: appTarget, activeBlock: appMatch, category: category)
        }

        if let categoryTarget {
            let categoryMatch = activeBlocks.first { block in
                guard block.state.target.type == .category else { return false }
                guard block.rule?.enforcementMode != .monitorOnly else { return false }
                return block.state.target == categoryTarget
            }
            if let categoryMatch {
                return AppBlockMatch(kind: .category, target: categoryTarget, activeBlock: categoryMatch, category: category)
            }
        }
        return nil
    }

    private func performConfiguredAction(_ action: AppBlockEnforcementAction, for app: AppBlockCandidate) async throws -> Bool {
        switch action {
        case .showCountdownAndHide:
            let didHide = try await controller.hide(app)
            await controller.activateBlockerApp()
            return didHide
        case .hide:
            return try await controller.hide(app)
        case .terminate:
            return try await controller.terminate(app)
        case .notifyOnly:
            return true
        }
    }

    private func isProtected(_ app: AppBlockCandidate) -> Bool {
        let candidates = [app.identifier, app.displayName].compactMap { $0 }
        return candidates.contains { protectedAppIdentifiers.contains($0) }
    }

    private func logAuditEvent(_ result: AppBlockEnforcementResult) throws {
        try BlockRuleStore.appendAuditEvent(BlockAuditEvent(
            timestamp: result.enforcedAt,
            kind: .blockDenied,
            target: result.match.target,
            ruleID: result.match.activeBlock.state.ruleID,
            message: "App block enforcement applied",
            metadata: [
                "appIdentifier": result.app.identifier,
                "appDisplayName": result.app.displayName ?? "",
                "matchKind": result.match.kind.rawValue,
                "category": result.match.category ?? "",
                "action": result.action.rawValue,
                "didPerformAction": String(result.didPerformAction),
                "blockedUntil": String(result.blockedUntil.timeIntervalSince1970),
                "error": result.errorDescription ?? ""
            ]
        ))
    }
}

#if canImport(AppKit)
struct LiveAppBlockController: AppBlockControlling {
    nonisolated init() {}

    func hide(_ app: AppBlockCandidate) async throws -> Bool {
        await MainActor.run {
            runningApplication(for: app)?.hide() ?? false
        }
    }

    func terminate(_ app: AppBlockCandidate) async throws -> Bool {
        await MainActor.run {
            runningApplication(for: app)?.terminate() ?? false
        }
    }

    func activateBlockerApp() async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    private func runningApplication(for app: AppBlockCandidate) -> NSRunningApplication? {
        if let pid = app.processIdentifier {
            return NSRunningApplication(processIdentifier: pid)
        }
        return NSWorkspace.shared.runningApplications.first { running in
            running.bundleIdentifier == app.identifier || running.localizedName == app.identifier
        }
    }
}

final class AppBlockNoticeWindowPresenter: AppBlockNoticePresenting, @unchecked Sendable {
    static let shared = AppBlockNoticeWindowPresenter()

    private init() {}

    func showBlockNotice(for app: AppBlockCandidate, match: AppBlockMatch, until blockedUntil: Date, action: AppBlockEnforcementAction) async {
        await MainActor.run {
            AppBlockNoticeWindowController.shared.show(app: app, match: match, blockedUntil: blockedUntil, action: action)
        }
    }
}

@MainActor
final class AppBlockNoticeWindowController {
    static let shared = AppBlockNoticeWindowController()

    private var window: NSWindow?
    private var timer: Timer?
    private let messageLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var blockedUntil = Date()
    private var appName = "App"
    private var category: String?

    private init() {}

    func show(app: AppBlockCandidate, match: AppBlockMatch, blockedUntil: Date, action: AppBlockEnforcementAction) {
        self.blockedUntil = blockedUntil
        self.appName = app.displayName?.isEmpty == false ? app.displayName! : app.identifier
        self.category = match.category

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Blocked by time.md"
            panel.level = .floating
            panel.center()

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 12
            stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
            stack.translatesAutoresizingMaskIntoConstraints = false

            messageLabel.font = .systemFont(ofSize: 20, weight: .semibold)
            messageLabel.lineBreakMode = .byWordWrapping
            messageLabel.maximumNumberOfLines = 2
            detailLabel.font = .systemFont(ofSize: 14)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.lineBreakMode = .byWordWrapping
            detailLabel.maximumNumberOfLines = 5

            stack.addArrangedSubview(messageLabel)
            stack.addArrangedSubview(detailLabel)
            panel.contentView = stack
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
                stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
                stack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
            ])
            window = panel
        }

        updateLabels(action: action)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if Date() >= self.blockedUntil {
                    self.close()
                } else {
                    self.updateLabels(action: action)
                }
            }
        }
    }

    private func updateLabels(action: AppBlockEnforcementAction) {
        let remaining = max(0, Int(ceil(blockedUntil.timeIntervalSince(Date()))))
        let minutes = remaining / 60
        let seconds = remaining % 60
        let countdown = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        messageLabel.stringValue = "\(appName) is blocked for \(countdown)"
        let scope = category.map { " because its \($0) category is cooling down" } ?? " because it is cooling down"
        let actionText: String
        switch action {
        case .showCountdownAndHide, .hide:
            actionText = "time.md hid the app so you can switch to something else."
        case .terminate:
            actionText = "time.md requested the app to quit."
        case .notifyOnly:
            actionText = "time.md is only showing this reminder."
        }
        detailLabel.stringValue = "You opened \(appName)\(scope). It will become available at \(blockedUntil.formatted(date: .omitted, time: .shortened)). \(actionText)"
    }

    private func close() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }
}

final class AppBlockActivationWatcher: @unchecked Sendable {
    static let shared = AppBlockActivationWatcher()

    private let enforcer: AppBlockEnforcer
    private var observer: NSObjectProtocol?

    init(enforcer: AppBlockEnforcer = .live) {
        self.enforcer = enforcer
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.enforce(running)
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            enforce(frontmost)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func enforce(_ running: NSRunningApplication) {
        let identifier = running.bundleIdentifier ?? running.localizedName ?? ""
        let app = AppBlockCandidate(
            identifier: identifier,
            displayName: running.localizedName,
            processIdentifier: running.processIdentifier
        )
        Task { _ = await enforcer.enforceIfNeeded(for: app) }
    }
}
#endif
