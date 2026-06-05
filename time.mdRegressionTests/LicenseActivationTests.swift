import XCTest
@testable import time_md

@MainActor
final class LicenseActivationTests: XCTestCase {
    func testActivationKeyFormatterAcceptsUngroupedPastes() {
        XCTAssertEqual(
            LicenseActivationKeyFormatter.normalized(" tmd abcd efgh jklm npqr stuv "),
            "TMD-ABCD-EFGH-JKLM-NPQR-STUV"
        )
        XCTAssertEqual(
            LicenseActivationKeyFormatter.normalized("tmdabcdefghjklmnpqrstuv"),
            "TMD-ABCD-EFGH-JKLM-NPQR-STUV"
        )
        XCTAssertEqual(
            LicenseActivationKeyFormatter.normalized("already-custom"),
            "ALREADY-CUSTOM"
        )
    }

    func testActivateStoresNormalizedKeyAndMetadata() async {
        let service = StubLicenseActivationService(activationResult: .success(.activeFixture()))
        let credentials = InMemoryActivationCredentialStore()
        let metadataStore = InMemoryActivationMetadataStore()
        let store = LicenseActivationStore(
            service: service,
            credentials: credentials,
            metadataStore: metadataStore,
            appVersionProvider: { "2.5.0-test" }
        )

        await store.activate(with: "tmdabcdefghjklmnpqrstuv")

        XCTAssertTrue(store.isUnlockedForLaunch)
        XCTAssertTrue(store.isPaidActivated)
        XCTAssertEqual(store.phase, .activated)
        XCTAssertEqual(credentials.activationKey, "TMD-ABCD-EFGH-JKLM-NPQR-STUV")
        XCTAssertNil(credentials.trialToken)
        XCTAssertEqual(metadataStore.metadata?.licenseID, "lic_test")
        XCTAssertNil(metadataStore.trialMetadata)
        XCTAssertEqual(service.activationRequests.first?.activationKey, "TMD-ABCD-EFGH-JKLM-NPQR-STUV")
        XCTAssertEqual(service.activationRequests.first?.deviceID, "device-test")
        XCTAssertEqual(service.activationRequests.first?.appVersion, "2.5.0-test")
    }

    func testActivateTrialStoresTokenAndUnlocks() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let service = StubLicenseActivationService(trialVerifyResult: .success(.trialFixture(now: now)))
        let credentials = InMemoryActivationCredentialStore()
        let metadataStore = InMemoryActivationMetadataStore()
        let store = LicenseActivationStore(
            service: service,
            credentials: credentials,
            metadataStore: metadataStore,
            appVersionProvider: { "2.5.0-test" },
            nowProvider: { now }
        )

        await store.activateTrial(with: "tmdtrial-token-test")

        XCTAssertTrue(store.isUnlockedForLaunch)
        XCTAssertTrue(store.isTrialActive)
        XCTAssertEqual(store.phase, .trialing)
        XCTAssertEqual(credentials.trialToken, "TMDTRIAL-TOKEN-TEST")
        XCTAssertEqual(metadataStore.trialMetadata?.trialID, "trial_test")
        XCTAssertEqual(service.trialActivationRequests.first?.trialToken, "TMDTRIAL-TOKEN-TEST")
        XCTAssertEqual(service.trialActivationRequests.first?.deviceID, "device-test")
        XCTAssertEqual(service.trialActivationRequests.first?.appVersion, "2.5.0-test")
    }

    func testCreateTrialCheckoutURLRequestsAppReturn() async {
        let service = StubLicenseActivationService(trialCheckoutURL: URL(string: "https://checkout.stripe.test/session")!)
        let store = LicenseActivationStore(service: service)

        let url = await store.createTrialCheckoutURL()

        XCTAssertEqual(url?.absoluteString, "https://checkout.stripe.test/session")
        XCTAssertEqual(store.phase, .needsActivation)
        XCTAssertEqual(service.trialCheckoutRequests.first?.source, "time.md macOS app paywall")
        XCTAssertEqual(service.trialCheckoutRequests.first?.returnToApp, true)
    }

    func testDeepLinkCheckoutSessionActivatesTrial() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let service = StubLicenseActivationService(
            trialVerifyResult: .success(.trialFixture(now: now)),
            checkoutTrialTokenResult: .success("TMDTRIAL-DEEP-LINK")
        )
        let credentials = InMemoryActivationCredentialStore()
        let metadataStore = InMemoryActivationMetadataStore()
        let store = LicenseActivationStore(
            service: service,
            credentials: credentials,
            metadataStore: metadataStore,
            appVersionProvider: { "2.5.0-test" },
            nowProvider: { now }
        )

        await store.activateTrial(fromCheckoutSessionID: "cs_test_deeplink")

        XCTAssertTrue(store.isUnlockedForLaunch)
        XCTAssertEqual(credentials.trialToken, "TMDTRIAL-DEEP-LINK")
        XCTAssertEqual(service.checkoutSessionRequests, ["cs_test_deeplink"])
        XCTAssertEqual(service.trialActivationRequests.first?.trialToken, "TMDTRIAL-DEEP-LINK")
    }

    func testTrialCheckoutSessionIDParsesCustomScheme() {
        let url = URL(string: "timemd://activate-trial?session_id=cs_test_123")!

        XCTAssertEqual(LicenseActivationStore.trialCheckoutSessionID(from: url), "cs_test_123")
        XCTAssertNil(LicenseActivationStore.trialCheckoutSessionID(from: URL(string: "https://timemd.isolated.tech/trial-success.html?session_id=cs_test_123")!))
        XCTAssertNil(LicenseActivationStore.trialCheckoutSessionID(from: URL(string: "timemd://activate-trial?session_id=bad")!))
    }

    func testPrepareForLaunchUnlocksCachedActivation() async {
        let service = StubLicenseActivationService(activationResult: .success(.activeFixture(licenseID: "lic_refreshed")))
        let credentials = InMemoryActivationCredentialStore(activationKey: "TMD-ABCD-EFGH-JKLM-NPQR-STUV")
        let metadataStore = InMemoryActivationMetadataStore(metadata: .activeFixture(licenseID: "lic_cached"))
        let store = LicenseActivationStore(service: service, credentials: credentials, metadataStore: metadataStore)

        await store.prepareForLaunch()

        XCTAssertTrue(store.isUnlockedForLaunch)
        XCTAssertEqual(store.phase, .activated)
        XCTAssertEqual(store.metadata?.licenseID, "lic_cached")
    }

    func testPrepareForLaunchUnlocksCachedTrial() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let service = StubLicenseActivationService(trialVerifyResult: .success(.trialFixture(now: now)))
        let credentials = InMemoryActivationCredentialStore(trialToken: "trial-token-test")
        let metadataStore = InMemoryActivationMetadataStore(trialMetadata: .trialFixture(now: now))
        let store = LicenseActivationStore(
            service: service,
            credentials: credentials,
            metadataStore: metadataStore,
            nowProvider: { now }
        )

        await store.prepareForLaunch()

        XCTAssertTrue(store.isUnlockedForLaunch)
        XCTAssertTrue(store.isTrialActive)
        XCTAssertEqual(store.phase, .trialing)
        XCTAssertEqual(store.trialMetadata?.trialID, "trial_test")
    }

    func testExpiredCachedTrialDoesNotUnlock() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let expiredTrial = TrialActivationMetadata.trialFixture(
            now: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )
        let credentials = InMemoryActivationCredentialStore(trialToken: "trial-token-test")
        let metadataStore = InMemoryActivationMetadataStore(trialMetadata: expiredTrial)
        let store = LicenseActivationStore(
            credentials: credentials,
            metadataStore: metadataStore,
            nowProvider: { now }
        )

        await store.prepareForLaunch()

        XCTAssertFalse(store.isUnlockedForLaunch)
        XCTAssertNil(credentials.trialToken)
        XCTAssertNil(metadataStore.trialMetadata)
        XCTAssertEqual(store.phase, .needsActivation)
    }

    func testInvalidRevalidationClearsStoredActivation() async {
        let service = StubLicenseActivationService(activationResult: .failure(LicenseActivationError.invalidKey("Activation key is revoked.")))
        let credentials = InMemoryActivationCredentialStore(activationKey: "TMD-ABCD-EFGH-JKLM-NPQR-STUV")
        let metadataStore = InMemoryActivationMetadataStore(metadata: .activeFixture())
        let store = LicenseActivationStore(service: service, credentials: credentials, metadataStore: metadataStore)

        await store.revalidateSavedActivation()

        XCTAssertFalse(store.isUnlockedForLaunch)
        XCTAssertNil(store.metadata)
        XCTAssertNil(credentials.activationKey)
        XCTAssertNil(metadataStore.metadata)
        XCTAssertEqual(store.phase, .failed("Activation key is revoked."))
    }

    func testExpiredTrialRevalidationClearsStoredTrial() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let service = StubLicenseActivationService(trialVerifyResult: .failure(LicenseActivationError.trialExpired("Your 14-day trial has expired.")))
        let credentials = InMemoryActivationCredentialStore(trialToken: "trial-token-test")
        let metadataStore = InMemoryActivationMetadataStore(trialMetadata: .trialFixture(now: now))
        let store = LicenseActivationStore(
            service: service,
            credentials: credentials,
            metadataStore: metadataStore,
            nowProvider: { now }
        )

        await store.revalidateSavedTrial()

        XCTAssertFalse(store.isUnlockedForLaunch)
        XCTAssertNil(store.trialMetadata)
        XCTAssertNil(credentials.trialToken)
        XCTAssertNil(metadataStore.trialMetadata)
        XCTAssertEqual(store.phase, .failed("Your 14-day trial has expired."))
    }
}

private struct StubActivationRequest: Equatable {
    var activationKey: String
    var deviceID: String
    var appVersion: String
}

private struct StubTrialRequest: Equatable {
    var trialToken: String?
    var deviceID: String
    var appVersion: String
}

private struct StubTrialCheckoutRequest: Equatable {
    var source: String
    var returnToApp: Bool
}

private final class StubLicenseActivationService: LicenseActivationServicing {
    var activationResult: Result<LicenseActivationMetadata, Error>
    var trialVerifyResult: Result<TrialActivationMetadata, Error>
    var trialCheckoutURL: URL
    var checkoutTrialTokenResult: Result<String, Error>
    private(set) var activationRequests: [StubActivationRequest] = []
    private(set) var trialActivationRequests: [StubTrialRequest] = []
    private(set) var trialVerifyRequests: [StubTrialRequest] = []
    private(set) var trialCheckoutRequests: [StubTrialCheckoutRequest] = []
    private(set) var checkoutSessionRequests: [String] = []

    init(
        activationResult: Result<LicenseActivationMetadata, Error> = .success(.activeFixture()),
        trialVerifyResult: Result<TrialActivationMetadata, Error> = .success(.trialFixture()),
        trialCheckoutURL: URL = URL(string: "https://checkout.stripe.test/session")!,
        checkoutTrialTokenResult: Result<String, Error> = .success("TMDTRIAL-STUB-TOKEN")
    ) {
        self.activationResult = activationResult
        self.trialVerifyResult = trialVerifyResult
        self.trialCheckoutURL = trialCheckoutURL
        self.checkoutTrialTokenResult = checkoutTrialTokenResult
    }

    func activate(activationKey: String, deviceID: String, appVersion: String) async throws -> LicenseActivationMetadata {
        activationRequests.append(StubActivationRequest(activationKey: activationKey, deviceID: deviceID, appVersion: appVersion))
        return try activationResult.get()
    }

    func activateTrial(trialToken: String, deviceID: String, appVersion: String) async throws -> TrialActivationMetadata {
        trialActivationRequests.append(StubTrialRequest(trialToken: trialToken, deviceID: deviceID, appVersion: appVersion))
        return try trialVerifyResult.get()
    }

    func verifyTrial(trialToken: String, deviceID: String, appVersion: String) async throws -> TrialActivationMetadata {
        trialVerifyRequests.append(StubTrialRequest(trialToken: trialToken, deviceID: deviceID, appVersion: appVersion))
        return try trialVerifyResult.get()
    }

    func createTrialCheckoutSession(source: String, returnToApp: Bool) async throws -> URL {
        trialCheckoutRequests.append(StubTrialCheckoutRequest(source: source, returnToApp: returnToApp))
        return trialCheckoutURL
    }

    func trialToken(checkoutSessionID: String) async throws -> String {
        checkoutSessionRequests.append(checkoutSessionID)
        return try checkoutTrialTokenResult.get()
    }
}

private final class InMemoryActivationCredentialStore: LicenseActivationCredentialStoring {
    var activationKey: String?
    var trialToken: String?
    var deviceID: String

    init(activationKey: String? = nil, trialToken: String? = nil, deviceID: String = "device-test") {
        self.activationKey = activationKey
        self.trialToken = trialToken
        self.deviceID = deviceID
    }

    func readActivationKey() throws -> String? { activationKey }
    func saveActivationKey(_ key: String) throws { activationKey = key }
    func deleteActivationKey() throws { activationKey = nil }
    func readTrialToken() throws -> String? { trialToken }
    func saveTrialToken(_ token: String) throws { trialToken = token }
    func deleteTrialToken() throws { trialToken = nil }
    func readOrCreateDeviceID() throws -> String { deviceID }
}

private final class InMemoryActivationMetadataStore: LicenseActivationMetadataStoring {
    var metadata: LicenseActivationMetadata?
    var trialMetadata: TrialActivationMetadata?

    init(metadata: LicenseActivationMetadata? = nil, trialMetadata: TrialActivationMetadata? = nil) {
        self.metadata = metadata
        self.trialMetadata = trialMetadata
    }

    func loadMetadata() -> LicenseActivationMetadata? { metadata }
    func saveMetadata(_ metadata: LicenseActivationMetadata) { self.metadata = metadata }
    func deleteMetadata() { metadata = nil }
    func loadTrialMetadata() -> TrialActivationMetadata? { trialMetadata }
    func saveTrialMetadata(_ metadata: TrialActivationMetadata) { trialMetadata = metadata }
    func deleteTrialMetadata() { trialMetadata = nil }
}

private extension LicenseActivationMetadata {
    static func activeFixture(licenseID: String = "lic_test") -> LicenseActivationMetadata {
        LicenseActivationMetadata(
            licenseID: licenseID,
            activationKeyPreview: "TMD-ABCD…STUV",
            stripeSessionID: "cs_test",
            status: "active",
            activatedAt: Date(timeIntervalSince1970: 1_000),
            lastValidatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }
}

private extension TrialActivationMetadata {
    static func trialFixture(
        now: Date = Date(timeIntervalSince1970: 10_000),
        expiresAt: Date? = nil
    ) -> TrialActivationMetadata {
        TrialActivationMetadata(
            trialID: "trial_test",
            trialTokenPreview: "trial…test",
            status: "trialing",
            startedAt: now,
            expiresAt: expiresAt ?? now.addingTimeInterval(14 * 86_400),
            lastValidatedAt: now
        )
    }
}
