import Foundation
import Security

protocol LicenseActivationCredentialStoring {
    func readActivationKey() throws -> String?
    func saveActivationKey(_ key: String) throws
    func deleteActivationKey() throws
    func readTrialToken() throws -> String?
    func saveTrialToken(_ token: String) throws
    func deleteTrialToken() throws
    func readOrCreateDeviceID() throws -> String
}

final class KeychainLicenseActivationCredentialStore: LicenseActivationCredentialStoring {
    private let service = "com.bontecou.time.md.activation"
    private let activationKeyAccount = "activation-key"
    private let trialTokenAccount = "trial-token"
    private let deviceIDAccount = "device-id"

    func readActivationKey() throws -> String? {
        try readString(account: activationKeyAccount)
    }

    func saveActivationKey(_ key: String) throws {
        try saveString(key, account: activationKeyAccount)
    }

    func deleteActivationKey() throws {
        try deleteString(account: activationKeyAccount)
    }

    func readTrialToken() throws -> String? {
        try readString(account: trialTokenAccount)
    }

    func saveTrialToken(_ token: String) throws {
        try saveString(token, account: trialTokenAccount)
    }

    func deleteTrialToken() throws {
        try deleteString(account: trialTokenAccount)
    }

    func readOrCreateDeviceID() throws -> String {
        if let existing = try readString(account: deviceIDAccount), !existing.isEmpty {
            return existing
        }

        let deviceID = UUID().uuidString.lowercased()
        try saveString(deviceID, account: deviceIDAccount)
        return deviceID
    }

    private func readString(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw LicenseActivationError.keychain(keychainMessage(status: status, action: "read"))
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw LicenseActivationError.keychain("Keychain returned unreadable activation data.")
        }
        return value
    }

    private func saveString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery = baseQuery(account: account)
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw LicenseActivationError.keychain(keychainMessage(status: updateStatus, action: "update"))
            }
            return
        }

        guard status == errSecSuccess else {
            throw LicenseActivationError.keychain(keychainMessage(status: status, action: "save"))
        }
    }

    private func deleteString(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else {
            throw LicenseActivationError.keychain(keychainMessage(status: status, action: "delete"))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainMessage(status: OSStatus, action: String) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "Could not \(action) activation data in Keychain: \(message)"
        }
        return "Could not \(action) activation data in Keychain (OSStatus \(status))."
    }
}

protocol LicenseActivationMetadataStoring {
    func loadMetadata() -> LicenseActivationMetadata?
    func saveMetadata(_ metadata: LicenseActivationMetadata)
    func deleteMetadata()
    func loadTrialMetadata() -> TrialActivationMetadata?
    func saveTrialMetadata(_ metadata: TrialActivationMetadata)
    func deleteTrialMetadata()
}

struct UserDefaultsLicenseActivationMetadataStore: LicenseActivationMetadataStoring {
    private let key = "timeMdLicenseActivationMetadata"
    private let trialKey = "timeMdTrialActivationMetadata"
    var defaults: UserDefaults = .standard

    func loadMetadata() -> LicenseActivationMetadata? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LicenseActivationMetadata.self, from: data)
    }

    func saveMetadata(_ metadata: LicenseActivationMetadata) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        defaults.set(data, forKey: key)
    }

    func deleteMetadata() {
        defaults.removeObject(forKey: key)
    }

    func loadTrialMetadata() -> TrialActivationMetadata? {
        guard let data = defaults.data(forKey: trialKey) else { return nil }
        return try? JSONDecoder().decode(TrialActivationMetadata.self, from: data)
    }

    func saveTrialMetadata(_ metadata: TrialActivationMetadata) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        defaults.set(data, forKey: trialKey)
    }

    func deleteTrialMetadata() {
        defaults.removeObject(forKey: trialKey)
    }
}
