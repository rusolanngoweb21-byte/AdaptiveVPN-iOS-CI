import Foundation
import Security

enum SecureInstallationSecretError: Error {
    case randomGeneration(OSStatus)
    case keychain(OSStatus)
    case malformedStoredValue
}

final class SecureInstallationSecret {
    static let shared = SecureInstallationSecret()

    private let service = "com.adaptivevpn.installation"
    private let account = "v1"

    private init() {}

    func getOrCreate() throws -> Data {
        if let existing = try read() {
            guard existing.count == 32 else {
                throw SecureInstallationSecretError.malformedStoredValue
            }
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else {
            throw SecureInstallationSecretError.randomGeneration(randomStatus)
        }

        let secret = Data(bytes)
        try store(secret)
        return secret
    }

    private func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecureInstallationSecretError.keychain(status)
        }
        return result as? Data
    }

    private func store(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureInstallationSecretError.keychain(status)
        }
    }
}
