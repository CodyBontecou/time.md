import Foundation

struct LicenseActivationMetadata: Codable, Equatable {
    var licenseID: String
    var activationKeyPreview: String
    var stripeSessionID: String?
    var status: String
    var activatedAt: Date
    var lastValidatedAt: Date

    var isActive: Bool { status == "active" }
}

struct TrialActivationMetadata: Codable, Equatable {
    var trialID: String
    var trialTokenPreview: String?
    var status: String
    var startedAt: Date
    var expiresAt: Date
    var lastValidatedAt: Date

    var isTrialing: Bool { status == "trialing" }
    var isConverted: Bool { status == "converted" || status == "active" }

    func isActive(at date: Date = Date()) -> Bool {
        isConverted || (isTrialing && expiresAt > date)
    }

    func daysRemaining(at date: Date = Date()) -> Int {
        guard isTrialing, expiresAt > date else { return 0 }
        return max(1, Int(ceil(expiresAt.timeIntervalSince(date) / 86_400)))
    }
}

enum LicenseActivationPhase: Equatable {
    case checking
    case needsActivation
    case activating
    case startingTrial
    case activated
    case trialing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .activating, .startingTrial:
            return true
        case .needsActivation, .activated, .trialing, .failed:
            return false
        }
    }
}

enum LicenseActivationKeyFormatter {
    static func normalized(_ value: String) -> String {
        let uppercased = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let compact = uppercased.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()

        guard compact.hasPrefix("TMD"), compact.count == 23 else {
            return uppercased
        }

        let payload = Array(compact.dropFirst(3))
        var groups: [String] = []
        for offset in stride(from: 0, to: payload.count, by: 4) {
            let end = min(offset + 4, payload.count)
            groups.append(String(payload[offset..<end]))
        }

        return (["TMD"] + groups).joined(separator: "-")
    }

    static func preview(_ value: String) -> String {
        let normalizedKey = normalized(value)
        guard normalizedKey.count > 14 else { return normalizedKey }
        return "\(normalizedKey.prefix(8))…\(normalizedKey.suffix(4))"
    }
}

struct LicenseActivationRequest: Encodable {
    var activationKey: String
    var deviceID: String
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case activationKey = "activation_key"
        case deviceID = "device_id"
        case appVersion = "app_version"
    }
}

struct TrialVerifyRequest: Encodable {
    var trialToken: String
    var deviceID: String
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case trialToken = "trial_token"
        case deviceID = "device_id"
        case appVersion = "app_version"
    }
}

struct TrialCheckoutSessionRequest: Encodable {
    var source: String
    var returnToApp: Bool

    enum CodingKeys: String, CodingKey {
        case source
        case returnToApp = "return_to_app"
    }
}

struct TrialCheckoutSessionAPIResponse: Decodable {
    var url: String?
    var id: String?
    var error: String?
}

struct LicenseActivationAPIResponse: Decodable {
    var valid: Bool?
    var status: String?
    var licenseID: String?
    var activationKeyPreview: String?
    var stripeSessionID: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case valid
        case status
        case licenseID = "license_id"
        case activationKeyPreview = "activation_key_preview"
        case stripeSessionID = "stripe_session_id"
        case error
    }
}

struct TrialActivationAPIResponse: Decodable {
    var valid: Bool?
    var status: String?
    var trialID: String?
    var trialToken: String?
    var trialTokenPreview: String?
    var startedAt: String?
    var expiresAt: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case valid
        case status
        case trialID = "trial_id"
        case trialToken = "trial_token"
        case trialTokenPreview = "trial_token_preview"
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case error
    }
}

enum LicenseActivationError: LocalizedError {
    case invalidKey(String)
    case trialExpired(String)
    case trialInvalid(String)
    case server(String)
    case missingResponseData
    case invalidDeepLink
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey(let message):
            return message
        case .trialExpired(let message):
            return message
        case .trialInvalid(let message):
            return message
        case .server(let message):
            return message
        case .missingResponseData:
            return "The activation server returned an unexpected response."
        case .invalidDeepLink:
            return "The trial return link was missing a valid Stripe Checkout session."
        case .keychain(let message):
            return message
        }
    }
}
