import Foundation

/// Local native-messaging protocol for optional browser extensions. The bridge
/// accepts only URL access events from trusted browser extension manifests and
/// turns them into the same domain access events as browser-history polling.
struct BrowserExtensionURLAccessMessage: Codable, Hashable, Sendable {
    var type: String
    var url: String
    var title: String?
    var browser: String?
    var profile: String?
    var tabID: Int?
    var frameID: Int?
    var occurredAt: Date?

    enum CodingKeys: String, CodingKey {
        case type
        case url
        case title
        case browser
        case profile
        case tabID = "tabId"
        case frameID = "frameId"
        case occurredAt
    }
}

enum BrowserExtensionBridgeAction: String, Codable, Sendable {
    case allow
    case block
    case ignored
    case invalid
}

struct BrowserExtensionBridgeResponse: Codable, Hashable, Sendable {
    var version: Int
    var action: BrowserExtensionBridgeAction
    var targetDomain: String?
    var blockedUntil: Date?
    var remainingSeconds: TimeInterval?
    var reason: String?

    static func invalid(_ reason: String) -> BrowserExtensionBridgeResponse {
        BrowserExtensionBridgeResponse(version: 1, action: .invalid, targetDomain: nil, blockedUntil: nil, remainingSeconds: nil, reason: reason)
    }

    static func ignored(_ reason: String, targetDomain: String? = nil) -> BrowserExtensionBridgeResponse {
        BrowserExtensionBridgeResponse(version: 1, action: .ignored, targetDomain: targetDomain, blockedUntil: nil, remainingSeconds: nil, reason: reason)
    }
}

enum BrowserExtensionBridgeError: LocalizedError, Equatable, Sendable {
    case messageTooLarge(Int)
    case invalidJSON
    case unsupportedType(String)
    case missingURL
    case unsupportedScheme(String?)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case let .messageTooLarge(size):
            return "Browser extension message is too large (\(size) bytes)."
        case .invalidJSON:
            return "Browser extension message is not valid JSON."
        case let .unsupportedType(type):
            return "Unsupported browser extension message type: \(type)."
        case .missingURL:
            return "Browser extension URL event is missing a URL."
        case let .unsupportedScheme(scheme):
            return "Browser extension URL scheme is not supported: \(scheme ?? "none")."
        case let .invalidURL(url):
            return "Browser extension URL is invalid: \(url)."
        }
    }
}

struct BrowserExtensionBridge: Sendable {
    var engineFactory: @Sendable () -> BlockPolicyEngine
    var deduplicator: WebsiteAccessDeduplicator
    var now: @Sendable () -> Date
    var maximumMessageBytes: Int

    init(
        engineFactory: @escaping @Sendable () -> BlockPolicyEngine = { BlockPolicyEngine() },
        deduplicator: WebsiteAccessDeduplicator = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        maximumMessageBytes: Int = 64 * 1024
    ) {
        self.engineFactory = engineFactory
        self.deduplicator = deduplicator
        self.now = now
        self.maximumMessageBytes = maximumMessageBytes
    }

    func handleJSONMessage(_ data: Data, source: String = "extension") -> BrowserExtensionBridgeResponse {
        do {
            let event = try parseURLAccessMessage(data)
            return try handle(event, source: source)
        } catch let error as BrowserExtensionBridgeError {
            return .invalid(error.localizedDescription)
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    func parseURLAccessMessage(_ data: Data) throws -> BrowserExtensionURLAccessMessage {
        guard data.count <= maximumMessageBytes else { throw BrowserExtensionBridgeError.messageTooLarge(data.count) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            if let string = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter().date(from: string) { return date }
                if let timestamp = Double(string) { return Date(timeIntervalSince1970: timestamp) }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date value")
        }

        let message: BrowserExtensionURLAccessMessage
        do {
            message = try decoder.decode(BrowserExtensionURLAccessMessage.self, from: data)
        } catch {
            throw BrowserExtensionBridgeError.invalidJSON
        }

        guard message.type == "urlAccess" else { throw BrowserExtensionBridgeError.unsupportedType(message.type) }
        guard !message.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BrowserExtensionBridgeError.missingURL }
        _ = try normalizedHTTPURL(message.url)
        return message
    }

    func handle(_ message: BrowserExtensionURLAccessMessage, source: String = "extension") throws -> BrowserExtensionBridgeResponse {
        let normalized = try normalizedHTTPURL(message.url)
        let target = try BlockTarget.domain(normalized.absoluteString)
        let relatedTargets = suffixDomainTargets(for: target.value).filter { $0 != target }
        let occurredAt = message.occurredAt ?? now()

        guard deduplicator.shouldProcess(domain: target.value, url: normalized.absoluteString, occurredAt: occurredAt, source: source) else {
            return .ignored("Duplicate URL event suppressed.", targetDomain: target.value)
        }

        let event = BlockAccessEvent(
            target: target,
            relatedTargets: relatedTargets,
            occurredAt: occurredAt,
            observedDurationSeconds: nil
        )
        let decision = try engineFactory().handleAccess(event)
        return response(for: decision, targetDomain: target.value, now: occurredAt)
    }

    private func response(for decision: BlockPolicyDecision, targetDomain: String, now: Date) -> BrowserExtensionBridgeResponse {
        switch decision.kind {
        case .ignored:
            return .ignored(decision.reason ?? "No matching rule.", targetDomain: targetDomain)
        case .allowedAndStartedCooldown:
            return BrowserExtensionBridgeResponse(
                version: 1,
                action: .allow,
                targetDomain: targetDomain,
                blockedUntil: decision.blockedUntil,
                remainingSeconds: decision.blockedUntil.map { max(0, $0.timeIntervalSince(now)) },
                reason: "Access allowed; cooldown scheduled."
            )
        case .deniedActiveBlock:
            return BrowserExtensionBridgeResponse(
                version: 1,
                action: .block,
                targetDomain: targetDomain,
                blockedUntil: decision.blockedUntil,
                remainingSeconds: decision.blockedUntil.map { max(0, $0.timeIntervalSince(now)) },
                reason: decision.reason ?? "Domain is currently blocked."
            )
        }
    }

    private func normalizedHTTPURL(_ rawURL: String) throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            throw BrowserExtensionBridgeError.invalidURL(rawURL)
        }
        guard scheme == "http" || scheme == "https" else {
            throw BrowserExtensionBridgeError.unsupportedScheme(components.scheme)
        }
        guard let url = components.url else { throw BrowserExtensionBridgeError.invalidURL(rawURL) }
        return url
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

enum BrowserExtensionNativeMessageCodec {
    /// Chrome/Firefox native messaging frames JSON with a little-endian UInt32
    /// byte length. This helper is pure so command-line host plumbing can be
    /// tested without launching a browser.
    static func encode(_ response: BrowserExtensionBridgeResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let payload = try encoder.encode(response)
        var length = UInt32(payload.count).littleEndian
        var framed = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        framed.append(payload)
        return framed
    }

    static func decode(_ data: Data, maximumMessageBytes: Int = 64 * 1024) throws -> Data {
        guard data.count >= MemoryLayout<UInt32>.size else { throw BrowserExtensionBridgeError.invalidJSON }
        let length = data.prefix(4).withUnsafeBytes { pointer in
            pointer.load(as: UInt32.self).littleEndian
        }
        guard length <= maximumMessageBytes else { throw BrowserExtensionBridgeError.messageTooLarge(Int(length)) }
        let payloadStart = data.index(data.startIndex, offsetBy: 4)
        let payloadEnd = data.index(payloadStart, offsetBy: Int(length), limitedBy: data.endIndex) ?? data.endIndex
        guard data.distance(from: payloadStart, to: payloadEnd) == Int(length) else { throw BrowserExtensionBridgeError.invalidJSON }
        return data[payloadStart..<payloadEnd]
    }
}
