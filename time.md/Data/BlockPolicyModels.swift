import Foundation

/// Validation failures for user-managed blocking rules and targets.
enum BlockRuleValidationError: LocalizedError, Equatable, Sendable {
    case emptyTarget(BlockTargetType)
    case invalidDomain(String)
    case invalidPolicy(String)

    var errorDescription: String? {
        switch self {
        case let .emptyTarget(type):
            return "A blocking target for \(type.displayName) cannot be empty."
        case let .invalidDomain(value):
            return "\(value) is not a valid domain or website URL."
        case let .invalidPolicy(message):
            return message
        }
    }
}

enum BlockTargetType: String, Codable, CaseIterable, Sendable {
    case domain
    case app
    case category

    var displayName: String {
        switch self {
        case .domain: return "Website"
        case .app: return "App"
        case .category: return "Category"
        }
    }
}

/// A normalized blocking target. `value` is used for matching and persistence;
/// `displayName` preserves a human-friendly label when normalization changes
/// casing/spacing (especially for categories and app names).
struct BlockTarget: Codable, Hashable, Sendable {
    let type: BlockTargetType
    let value: String
    let displayName: String?

    init(type: BlockTargetType, value rawValue: String, displayName rawDisplayName: String? = nil) throws {
        let normalized = try Self.normalizedValue(rawValue, for: type)
        self.type = type
        self.value = normalized.value
        self.displayName = rawDisplayName?.trimmedNonEmpty ?? normalized.displayName
    }

    static func domain(_ value: String, displayName: String? = nil) throws -> BlockTarget {
        try BlockTarget(type: .domain, value: value, displayName: displayName)
    }

    static func app(_ value: String, displayName: String? = nil) throws -> BlockTarget {
        try BlockTarget(type: .app, value: value, displayName: displayName)
    }

    static func category(_ value: String, displayName: String? = nil) throws -> BlockTarget {
        try BlockTarget(type: .category, value: value, displayName: displayName)
    }

    private static func normalizedValue(_ rawValue: String, for type: BlockTargetType) throws -> (value: String, displayName: String?) {
        switch type {
        case .domain:
            return (try normalizeDomain(rawValue), nil)
        case .app:
            let trimmed = rawValue.trimmedNonEmpty
            guard let trimmed else { throw BlockRuleValidationError.emptyTarget(type) }
            if trimmed.contains(".") {
                return (trimmed.lowercased(), rawValue.trimmedNonEmpty)
            }
            return (trimmed, trimmed)
        case .category:
            guard let collapsed = rawValue.collapsingWhitespace.trimmedNonEmpty else {
                throw BlockRuleValidationError.emptyTarget(type)
            }
            return (collapsed.lowercased(), collapsed)
        }
    }

    private static func normalizeDomain(_ rawValue: String) throws -> String {
        guard let trimmed = rawValue.trimmedNonEmpty else {
            throw BlockRuleValidationError.emptyTarget(.domain)
        }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else if trimmed.contains("/") || trimmed.contains("?") || trimmed.contains("#") {
            candidate = "https://\(trimmed)"
        } else {
            candidate = "https://\(trimmed)"
        }

        let host = URLComponents(string: candidate)?.host ?? trimmed
        var normalized = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        if normalized.hasPrefix("www.") {
            normalized.removeFirst(4)
        }

        let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/:@?#"))
        guard !normalized.isEmpty,
              normalized.rangeOfCharacter(from: invalidCharacters) == nil,
              normalized.contains("."),
              !normalized.hasPrefix("."),
              !normalized.hasSuffix(".") else {
            throw BlockRuleValidationError.invalidDomain(rawValue)
        }

        return normalized
    }
}

enum BlockDecayBehavior: String, Codable, CaseIterable, Sendable {
    case none
    case resetAfterIdle
    case stepDownAfterIdle
}

enum BlockEnforcementMode: String, Codable, CaseIterable, Sendable {
    /// Track rule matches and state but do not enforce an OS/app block.
    case monitorOnly
    /// Enforce through the domain blocker helper (`/etc/hosts`/`pf`) once implemented.
    case domainNetwork
    /// Enforce by hiding, redirecting, or terminating matching apps once implemented.
    case appFocus
}

/// Configuration for exponential cooldown progression.
struct BlockPolicy: Codable, Hashable, Sendable {
    let baseDurationSeconds: TimeInterval
    let multiplier: Double
    let maxDurationSeconds: TimeInterval
    let decayBehavior: BlockDecayBehavior
    let decayIntervalSeconds: TimeInterval?
    let gracePeriodSeconds: TimeInterval
    let minimumSessionSeconds: TimeInterval

    init(
        baseDurationSeconds: TimeInterval,
        multiplier: Double = 2,
        maxDurationSeconds: TimeInterval,
        decayBehavior: BlockDecayBehavior = .none,
        decayIntervalSeconds: TimeInterval? = nil,
        gracePeriodSeconds: TimeInterval = 0,
        minimumSessionSeconds: TimeInterval = 0
    ) throws {
        self.baseDurationSeconds = baseDurationSeconds
        self.multiplier = multiplier
        self.maxDurationSeconds = maxDurationSeconds
        self.decayBehavior = decayBehavior
        self.decayIntervalSeconds = decayIntervalSeconds
        self.gracePeriodSeconds = gracePeriodSeconds
        self.minimumSessionSeconds = minimumSessionSeconds
        try validate()
    }

    func validate() throws {
        guard baseDurationSeconds > 0 else {
            throw BlockRuleValidationError.invalidPolicy("Base block duration must be greater than zero.")
        }
        guard multiplier >= 1 else {
            throw BlockRuleValidationError.invalidPolicy("Block multiplier must be at least 1.0.")
        }
        guard maxDurationSeconds >= baseDurationSeconds else {
            throw BlockRuleValidationError.invalidPolicy("Maximum block duration must be at least the base duration.")
        }
        guard gracePeriodSeconds >= 0, minimumSessionSeconds >= 0 else {
            throw BlockRuleValidationError.invalidPolicy("Grace period and minimum session duration cannot be negative.")
        }
        if decayBehavior != .none {
            guard let decayIntervalSeconds, decayIntervalSeconds > 0 else {
                throw BlockRuleValidationError.invalidPolicy("Decay interval must be greater than zero when decay is enabled.")
            }
        }
    }

    static let defaultExponential = try! BlockPolicy(
        baseDurationSeconds: 60,
        multiplier: 2,
        maxDurationSeconds: 4 * 60 * 60
    )
}

struct BlockRule: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var target: BlockTarget
    var policy: BlockPolicy
    var enabled: Bool
    var enforcementMode: BlockEnforcementMode
    var priority: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        target: BlockTarget,
        policy: BlockPolicy = .defaultExponential,
        enabled: Bool = true,
        enforcementMode: BlockEnforcementMode? = nil,
        priority: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.target = target
        self.policy = policy
        self.enabled = enabled
        self.enforcementMode = enforcementMode ?? Self.defaultEnforcementMode(for: target.type)
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private static func defaultEnforcementMode(for type: BlockTargetType) -> BlockEnforcementMode {
        switch type {
        case .domain: return .domainNetwork
        case .app, .category: return .appFocus
        }
    }
}

/// Persisted cooldown/strike state. State is keyed by normalized target so it
/// can survive rule edits and remain independent from rule definitions.
struct BlockState: Codable, Hashable, Sendable {
    var target: BlockTarget
    var ruleID: UUID?
    var strikeCount: Int
    var blockedUntil: Date?
    var lastAllowedAt: Date?
    var lastBlockedAt: Date?
    var updatedAt: Date

    init(
        target: BlockTarget,
        ruleID: UUID? = nil,
        strikeCount: Int = 0,
        blockedUntil: Date? = nil,
        lastAllowedAt: Date? = nil,
        lastBlockedAt: Date? = nil,
        updatedAt: Date = Date()
    ) throws {
        guard strikeCount >= 0 else {
            throw BlockRuleValidationError.invalidPolicy("Strike count cannot be negative.")
        }
        self.target = target
        self.ruleID = ruleID
        self.strikeCount = strikeCount
        self.blockedUntil = blockedUntil
        self.lastAllowedAt = lastAllowedAt
        self.lastBlockedAt = lastBlockedAt
        self.updatedAt = updatedAt
    }
}

enum BlockAuditEventKind: String, Codable, CaseIterable, Sendable {
    case ruleCreated
    case ruleUpdated
    case ruleDeleted
    case stateUpdated
    case corruptRowSkipped
    case accessObserved
    case ruleMatched
    case blockStarted
    case blockDenied
    case blockExpired
}

struct BlockAuditEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var timestamp: Date
    var kind: BlockAuditEventKind
    var target: BlockTarget?
    var ruleID: UUID?
    var message: String
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: BlockAuditEventKind,
        target: BlockTarget? = nil,
        ruleID: UUID? = nil,
        message: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.target = target
        self.ruleID = ruleID
        self.message = message
        self.metadata = metadata
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var collapsingWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
