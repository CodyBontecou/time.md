import Foundation
import Observation

@MainActor
@Observable
final class LicenseActivationStore {
    static let shared = LicenseActivationStore()

    private(set) var phase: LicenseActivationPhase = .checking
    private(set) var metadata: LicenseActivationMetadata?
    private(set) var trialMetadata: TrialActivationMetadata?
    private(set) var statusMessage: String?

    @ObservationIgnored private let service: LicenseActivationServicing
    @ObservationIgnored private let credentials: LicenseActivationCredentialStoring
    @ObservationIgnored private let metadataStore: LicenseActivationMetadataStoring
    @ObservationIgnored private let appVersionProvider: () -> String
    @ObservationIgnored private let nowProvider: () -> Date
    @ObservationIgnored private var didPrepareForLaunch = false
    @ObservationIgnored private var checkoutSessionsInFlight: Set<String> = []

    init(
        service: LicenseActivationServicing = URLSessionLicenseActivationService(),
        credentials: LicenseActivationCredentialStoring = KeychainLicenseActivationCredentialStore(),
        metadataStore: LicenseActivationMetadataStoring = UserDefaultsLicenseActivationMetadataStore(),
        appVersionProvider: @escaping () -> String = LicenseActivationStore.currentAppVersion,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.credentials = credentials
        self.metadataStore = metadataStore
        self.appVersionProvider = appVersionProvider
        self.nowProvider = nowProvider
    }

    var isPaidActivated: Bool {
        metadata?.isActive == true
    }

    var isTrialActive: Bool {
        trialMetadata?.isActive(at: nowProvider()) == true
    }

    var isUnlockedForLaunch: Bool {
        isPaidActivated || isTrialActive
    }

    var hasSavedEntitlement: Bool {
        metadata != nil || trialMetadata != nil
    }

    var activationKeyPreview: String {
        metadata?.activationKeyPreview ?? "Not activated"
    }

    var entitlementTitle: String {
        if isPaidActivated { return "Activated" }
        if trialMetadata?.isConverted == true { return "Paid via trial" }
        if isTrialActive { return "14-day card trial active" }
        return "Activation required"
    }

    var entitlementDetail: String {
        if isPaidActivated {
            return "Key: \(activationKeyPreview) • Last verified: \(lastValidatedDescription)"
        }

        if let trialMetadata {
            return "Trial: \(trialRemainingDescription(for: trialMetadata)) • Last verified: \(lastValidatedDescription)"
        }

        return "Start a free trial or enter a license key."
    }

    var lastValidatedDescription: String {
        let date = metadata?.lastValidatedAt ?? trialMetadata?.lastValidatedAt
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func trialRemainingDescription(for trial: TrialActivationMetadata? = nil) -> String {
        guard let trial = trial ?? trialMetadata else { return "No trial" }
        if trial.isConverted { return "Converted to paid license" }
        guard trial.isActive(at: nowProvider()) else { return "Expired" }
        let days = trial.daysRemaining(at: nowProvider())
        return "\(days) day\(days == 1 ? "" : "s") remaining"
    }

    func prepareForLaunch() async {
        guard !didPrepareForLaunch else { return }
        didPrepareForLaunch = true

        #if DEBUG
        if ProcessInfo.processInfo.environment["TIMEMD_ACTIVATION_BYPASS"] == "1" {
            enableDebugBypass()
            return
        }
        #endif

        if restoreSavedPaidActivation() { return }
        if restoreSavedTrial() { return }

        phase = .needsActivation
        metadata = nil
        trialMetadata = nil
    }

    func activate(with rawActivationKey: String) async {
        let activationKey = LicenseActivationKeyFormatter.normalized(rawActivationKey)
        guard !activationKey.isEmpty else {
            phase = .failed("Enter the activation key from your checkout page or license email.")
            return
        }

        phase = .activating
        statusMessage = "Contacting activation server…"

        do {
            let deviceID = try credentials.readOrCreateDeviceID()
            var activatedMetadata = try await service.activate(
                activationKey: activationKey,
                deviceID: deviceID,
                appVersion: appVersionProvider()
            )
            let now = nowProvider()
            activatedMetadata.activatedAt = metadata?.activatedAt ?? now
            activatedMetadata.lastValidatedAt = now

            try credentials.saveActivationKey(activationKey)
            clearStoredTrial()
            metadataStore.saveMetadata(activatedMetadata)
            metadata = activatedMetadata
            phase = .activated
            statusMessage = "Activation complete. Your screen time data still stays on this Mac."
        } catch {
            phase = .failed(error.localizedDescription)
            statusMessage = nil
        }
    }

    func createTrialCheckoutURL() async -> URL? {
        phase = .startingTrial
        statusMessage = "Opening secure Stripe Checkout…"

        do {
            let url = try await service.createTrialCheckoutSession(
                source: "time.md macOS app paywall",
                returnToApp: true
            )
            phase = .needsActivation
            statusMessage = "Complete card setup in Stripe. time.md will reopen automatically after checkout."
            return url
        } catch {
            phase = .failed(error.localizedDescription)
            statusMessage = nil
            return nil
        }
    }

    func activateTrial(fromCheckoutSessionID rawSessionID: String) async {
        let sessionID = rawSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sessionID.hasPrefix("cs_") else {
            phase = .failed(LicenseActivationError.invalidDeepLink.localizedDescription)
            statusMessage = nil
            return
        }
        guard !checkoutSessionsInFlight.contains(sessionID) else { return }
        checkoutSessionsInFlight.insert(sessionID)
        defer { checkoutSessionsInFlight.remove(sessionID) }

        phase = .startingTrial
        statusMessage = "Completing trial activation from Stripe…"

        do {
            let trialToken = try await service.trialToken(checkoutSessionID: sessionID)
            await activateTrial(with: trialToken)
        } catch {
            phase = .failed(error.localizedDescription)
            statusMessage = nil
        }
    }

    func handleDeepLink(_ url: URL) {
        guard let sessionID = Self.trialCheckoutSessionID(from: url) else { return }
        Task { await activateTrial(fromCheckoutSessionID: sessionID) }
    }

    static func trialCheckoutSessionID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "timemd" else { return nil }

        let host = url.host?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "activate-trial" || host == "trial-success" || path == "activate-trial" || path == "trial-success" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sessionID = components.queryItems?.first(where: { $0.name == "session_id" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              sessionID.hasPrefix("cs_") else {
            return nil
        }

        return sessionID
    }

    func activateTrial(with rawTrialToken: String) async {
        let trialToken = rawTrialToken.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trialToken.isEmpty else {
            phase = .failed("Paste the trial key from your Stripe trial checkout page.")
            return
        }

        phase = .startingTrial
        statusMessage = "Activating your 14-day card-backed trial…"

        do {
            let deviceID = try credentials.readOrCreateDeviceID()
            var activatedTrial = try await service.activateTrial(
                trialToken: trialToken,
                deviceID: deviceID,
                appVersion: appVersionProvider()
            )
            activatedTrial.lastValidatedAt = nowProvider()

            try credentials.saveTrialToken(trialToken)
            metadataStore.saveTrialMetadata(activatedTrial)
            trialMetadata = activatedTrial
            phase = .trialing
            statusMessage = "Trial activated — \(trialRemainingDescription(for: activatedTrial)). Screen time data still stays on this Mac."
        } catch LicenseActivationError.trialExpired(let message) {
            clearStoredTrial()
            phase = .failed(message)
            statusMessage = nil
        } catch LicenseActivationError.trialInvalid(let message) {
            clearStoredTrial()
            phase = .failed(message)
            statusMessage = nil
        } catch {
            phase = .failed(error.localizedDescription)
            statusMessage = nil
        }
    }

    func revalidateCurrentEntitlement() async {
        if metadata?.isActive == true || metadataStore.loadMetadata()?.isActive == true {
            await revalidateSavedActivation()
            return
        }

        if trialMetadata?.isActive(at: nowProvider()) == true || metadataStore.loadTrialMetadata()?.isActive(at: nowProvider()) == true {
            await revalidateSavedTrial()
            return
        }

        phase = .needsActivation
        statusMessage = "Start a free trial or enter a license key."
    }

    func revalidateSavedActivation() async {
        guard let currentMetadata = metadataStore.loadMetadata(), currentMetadata.isActive else {
            clearStoredActivation()
            if !restoreSavedTrial() {
                phase = .needsActivation
            }
            return
        }

        do {
            guard let activationKey = try credentials.readActivationKey() else {
                clearStoredActivation(deleteCredential: false)
                if !restoreSavedTrial() {
                    phase = .needsActivation
                    statusMessage = "Activation key was missing from Keychain. Paste your key to activate again."
                }
                return
            }

            let deviceID = try credentials.readOrCreateDeviceID()
            var refreshedMetadata = try await service.activate(
                activationKey: activationKey,
                deviceID: deviceID,
                appVersion: appVersionProvider()
            )
            refreshedMetadata.activatedAt = currentMetadata.activatedAt
            refreshedMetadata.lastValidatedAt = nowProvider()
            metadataStore.saveMetadata(refreshedMetadata)
            metadata = refreshedMetadata
            phase = .activated
            statusMessage = "License verified."
        } catch LicenseActivationError.invalidKey(let message) {
            clearStoredActivation()
            if !restoreSavedTrial() {
                phase = .failed(message)
                statusMessage = nil
            }
        } catch {
            metadata = currentMetadata
            phase = .activated
            statusMessage = "Could not reverify right now (\(error.localizedDescription)). Continuing with saved activation."
        }
    }

    func revalidateSavedTrial() async {
        guard let currentTrial = metadataStore.loadTrialMetadata() else {
            clearStoredTrial()
            phase = .needsActivation
            return
        }

        guard currentTrial.isActive(at: nowProvider()) else {
            clearStoredTrial()
            phase = .failed("Your 14-day trial has expired. Buy a license or enter an activation key to continue.")
            statusMessage = nil
            return
        }

        do {
            guard let trialToken = try credentials.readTrialToken() else {
                clearStoredTrial(deleteCredential: false)
                phase = .needsActivation
                statusMessage = "Trial token was missing from Keychain. Start a trial or enter an activation key."
                return
            }

            let deviceID = try credentials.readOrCreateDeviceID()
            var refreshedTrial = try await service.verifyTrial(
                trialToken: trialToken,
                deviceID: deviceID,
                appVersion: appVersionProvider()
            )
            refreshedTrial.lastValidatedAt = nowProvider()
            metadataStore.saveTrialMetadata(refreshedTrial)
            trialMetadata = refreshedTrial
            phase = .trialing
            statusMessage = "Trial verified — \(trialRemainingDescription(for: refreshedTrial))."
        } catch LicenseActivationError.trialExpired(let message) {
            clearStoredTrial()
            phase = .failed(message)
            statusMessage = nil
        } catch LicenseActivationError.trialInvalid(let message) {
            clearStoredTrial()
            phase = .failed(message)
            statusMessage = nil
        } catch {
            trialMetadata = currentTrial
            phase = .trialing
            statusMessage = "Could not reverify trial right now (\(error.localizedDescription)). Continuing until \(currentTrial.expiresAt.formatted(date: .abbreviated, time: .shortened))."
        }
    }

    func resetActivation() {
        clearStoredActivation()
        clearStoredTrial()
        phase = .needsActivation
        statusMessage = "Activation and trial state were removed from this Mac."
    }

    private func restoreSavedPaidActivation() -> Bool {
        guard let cachedMetadata = metadataStore.loadMetadata(), cachedMetadata.isActive else {
            metadata = nil
            return false
        }

        do {
            guard try credentials.readActivationKey() != nil else {
                clearStoredActivation(deleteCredential: false)
                statusMessage = "Activation key was missing from Keychain. Paste your key to activate again."
                return false
            }
        } catch {
            clearStoredActivation(deleteCredential: false)
            statusMessage = error.localizedDescription
            return false
        }

        metadata = cachedMetadata
        phase = .activated
        statusMessage = "Using saved activation while verifying in the background."
        Task { await revalidateSavedActivation() }
        return true
    }

    private func restoreSavedTrial() -> Bool {
        guard let cachedTrial = metadataStore.loadTrialMetadata() else {
            trialMetadata = nil
            return false
        }

        guard cachedTrial.isActive(at: nowProvider()) else {
            clearStoredTrial()
            statusMessage = "Your 14-day trial has expired. Buy a license or enter an activation key to continue."
            return false
        }

        do {
            guard try credentials.readTrialToken() != nil else {
                clearStoredTrial(deleteCredential: false)
                statusMessage = "Trial token was missing from Keychain. Start a trial or enter an activation key."
                return false
            }
        } catch {
            clearStoredTrial(deleteCredential: false)
            statusMessage = error.localizedDescription
            return false
        }

        trialMetadata = cachedTrial
        phase = .trialing
        statusMessage = "Using saved trial while verifying in the background — \(trialRemainingDescription(for: cachedTrial))."
        Task { await revalidateSavedTrial() }
        return true
    }

    private func clearStoredActivation(deleteCredential: Bool = true) {
        if deleteCredential {
            try? credentials.deleteActivationKey()
        }
        metadataStore.deleteMetadata()
        metadata = nil
    }

    private func clearStoredTrial(deleteCredential: Bool = true) {
        if deleteCredential {
            try? credentials.deleteTrialToken()
        }
        metadataStore.deleteTrialMetadata()
        trialMetadata = nil
    }

    #if DEBUG
    private func enableDebugBypass() {
        let now = nowProvider()
        metadata = LicenseActivationMetadata(
            licenseID: "debug-bypass",
            activationKeyPreview: "DEBUG",
            stripeSessionID: nil,
            status: "active",
            activatedAt: now,
            lastValidatedAt: now
        )
        trialMetadata = nil
        phase = .activated
        statusMessage = "Debug activation bypass enabled. Release builds ignore TIMEMD_ACTIVATION_BYPASS."
    }
    #endif

    private static func currentAppVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        case (.none, .none):
            return "unknown"
        }
    }
}
