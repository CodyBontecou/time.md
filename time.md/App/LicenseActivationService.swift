import Foundation

protocol LicenseActivationServicing {
    func activate(activationKey: String, deviceID: String, appVersion: String) async throws -> LicenseActivationMetadata
    func activateTrial(trialToken: String, deviceID: String, appVersion: String) async throws -> TrialActivationMetadata
    func verifyTrial(trialToken: String, deviceID: String, appVersion: String) async throws -> TrialActivationMetadata
    func createTrialCheckoutSession(source: String, returnToApp: Bool) async throws -> URL
    func trialToken(checkoutSessionID: String) async throws -> String
}

struct URLSessionLicenseActivationService: LicenseActivationServicing {
    var activationEndpoint: URL
    var trialCheckoutEndpoint: URL
    var verifyTrialCheckoutEndpoint: URL
    var verifyTrialEndpoint: URL
    var session: URLSession

    init(
        endpoint: URL = LicenseActivationEndpoint.activationURL,
        trialCheckoutEndpoint: URL = LicenseActivationEndpoint.trialCheckoutURL,
        verifyTrialCheckoutEndpoint: URL = LicenseActivationEndpoint.verifyTrialCheckoutURL,
        verifyTrialEndpoint: URL = LicenseActivationEndpoint.verifyTrialURL,
        session: URLSession = .shared
    ) {
        self.activationEndpoint = endpoint
        self.trialCheckoutEndpoint = trialCheckoutEndpoint
        self.verifyTrialCheckoutEndpoint = verifyTrialCheckoutEndpoint
        self.verifyTrialEndpoint = verifyTrialEndpoint
        self.session = session
    }

    func activate(activationKey: String, deviceID: String, appVersion: String) async throws -> LicenseActivationMetadata {
        let (data, response) = try await post(
            LicenseActivationRequest(activationKey: activationKey, deviceID: deviceID, appVersion: appVersion),
            to: activationEndpoint
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.missingResponseData
        }

        let payload = try? JSONDecoder().decode(LicenseActivationAPIResponse.self, from: data)

        guard (200..<300).contains(httpResponse.statusCode) else {
            if payload?.valid == false || httpResponse.statusCode == 404 {
                let status = payload?.status ?? "not_found"
                throw LicenseActivationError.invalidKey("Activation key is \(status.replacingOccurrences(of: "_", with: " ")).")
            }

            throw LicenseActivationError.server(payload?.error ?? "Activation failed with HTTP \(httpResponse.statusCode).")
        }

        guard payload?.valid == true,
              payload?.status == "active",
              let licenseID = payload?.licenseID,
              let activationKeyPreview = payload?.activationKeyPreview else {
            throw LicenseActivationError.server(payload?.error ?? "Activation server did not confirm an active license.")
        }

        let now = Date()
        return LicenseActivationMetadata(
            licenseID: licenseID,
            activationKeyPreview: activationKeyPreview,
            stripeSessionID: payload?.stripeSessionID,
            status: payload?.status ?? "active",
            activatedAt: now,
            lastValidatedAt: now
        )
    }

    func activateTrial(trialToken: String, deviceID: String, appVersion: String) async throws -> TrialActivationMetadata {
        try await verifyTrial(trialToken: trialToken, deviceID: deviceID, appVersion: appVersion)
    }

    func createTrialCheckoutSession(source: String, returnToApp: Bool) async throws -> URL {
        let (data, response) = try await post(
            TrialCheckoutSessionRequest(source: source, returnToApp: returnToApp),
            to: trialCheckoutEndpoint
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.missingResponseData
        }

        let payload = try? JSONDecoder().decode(TrialCheckoutSessionAPIResponse.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LicenseActivationError.server(payload?.error ?? "Trial checkout failed with HTTP \(httpResponse.statusCode).")
        }

        guard let rawURL = payload?.url, let url = URL(string: rawURL) else {
            throw LicenseActivationError.server(payload?.error ?? "Trial checkout did not return a Stripe URL.")
        }

        return url
    }

    func trialToken(checkoutSessionID: String) async throws -> String {
        var components = URLComponents(url: verifyTrialCheckoutEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "session_id", value: checkoutSessionID)]
        guard let url = components?.url else {
            throw LicenseActivationError.invalidDeepLink
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.missingResponseData
        }

        let payload = try? JSONDecoder().decode(TrialActivationAPIResponse.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            if payload?.status == "expired" || httpResponse.statusCode == 410 {
                throw LicenseActivationError.trialExpired("Your 14-day trial has expired. Buy a license to continue.")
            }

            if payload?.valid == false {
                let status = payload?.status ?? "not_found"
                throw LicenseActivationError.trialInvalid("Trial checkout is \(status.replacingOccurrences(of: "_", with: " ")).")
            }

            throw LicenseActivationError.server(payload?.error ?? "Trial checkout verification failed with HTTP \(httpResponse.statusCode).")
        }

        guard payload?.valid == true, let trialToken = payload?.trialToken, !trialToken.isEmpty else {
            throw LicenseActivationError.server(payload?.error ?? "Trial checkout did not return a trial key.")
        }

        return trialToken
    }

    func verifyTrial(trialToken: String, deviceID: String, appVersion: String) async throws -> TrialActivationMetadata {
        let (data, response) = try await post(
            TrialVerifyRequest(trialToken: trialToken, deviceID: deviceID, appVersion: appVersion),
            to: verifyTrialEndpoint
        )
        return try decodeTrialResult(data: data, response: response)
    }

    private func post<Request: Encodable>(_ body: Request, to endpoint: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.httpBody = try JSONEncoder().encode(body)
        return try await session.data(for: request)
    }

    private func decodeTrialResult(data: Data, response: URLResponse) throws -> TrialActivationMetadata {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.missingResponseData
        }

        let payload = try? JSONDecoder().decode(TrialActivationAPIResponse.self, from: data)

        guard (200..<300).contains(httpResponse.statusCode) else {
            if payload?.status == "expired" || httpResponse.statusCode == 410 {
                throw LicenseActivationError.trialExpired("Your 14-day trial has expired. Buy a license to continue.")
            }

            if payload?.valid == false {
                let status = payload?.status ?? "not_found"
                throw LicenseActivationError.trialInvalid("Trial is \(status.replacingOccurrences(of: "_", with: " ")).")
            }

            throw LicenseActivationError.server(payload?.error ?? "Trial request failed with HTTP \(httpResponse.statusCode).")
        }

        let status = payload?.status ?? "unknown"
        guard payload?.valid == true,
              (status == "trialing" || status == "converted" || status == "active"),
              let trialID = payload?.trialID,
              let startedAt = parseDate(payload?.startedAt),
              let expiresAt = parseDate(payload?.expiresAt) else {
            throw LicenseActivationError.server(payload?.error ?? "Activation server did not confirm an active trial.")
        }

        let now = Date()
        return TrialActivationMetadata(
            trialID: trialID,
            trialTokenPreview: payload?.trialTokenPreview,
            status: status,
            startedAt: startedAt,
            expiresAt: expiresAt,
            lastValidatedAt: now
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = Self.iso8601WithFractionalSeconds.date(from: value) { return date }
        return Self.iso8601.date(from: value)
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()
}

enum LicenseActivationEndpoint {
    static var activationURL: URL {
        url(
            debugEnvironmentKey: "TIMEMD_ACTIVATION_URL",
            infoDictionaryKey: "TimeMdActivationURL",
            fallback: "https://timemd.isolated.tech/api/activate"
        )
    }

    static var trialCheckoutURL: URL {
        url(
            debugEnvironmentKey: "TIMEMD_TRIAL_CHECKOUT_URL",
            infoDictionaryKey: "TimeMdTrialCheckoutURL",
            fallback: "https://timemd.isolated.tech/api/create-trial-checkout-session"
        )
    }

    static var verifyTrialCheckoutURL: URL {
        url(
            debugEnvironmentKey: "TIMEMD_VERIFY_TRIAL_CHECKOUT_URL",
            infoDictionaryKey: "TimeMdVerifyTrialCheckoutURL",
            fallback: "https://timemd.isolated.tech/api/verify-trial-checkout-session"
        )
    }

    static var verifyTrialURL: URL {
        url(
            debugEnvironmentKey: "TIMEMD_VERIFY_TRIAL_URL",
            infoDictionaryKey: "TimeMdVerifyTrialURL",
            fallback: "https://timemd.isolated.tech/api/verify-trial"
        )
    }

    static var defaultURL: URL { activationURL }

    private static func url(debugEnvironmentKey: String, infoDictionaryKey: String, fallback: String) -> URL {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[debugEnvironmentKey],
           let url = URL(string: raw) {
            return url
        }
        #endif

        if let raw = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
           let url = URL(string: raw) {
            return url
        }

        return URL(string: fallback)!
    }
}
