import Foundation
import Security

struct MobileCredential: Codable, Equatable {
    let deviceId: String
    let refreshToken: String
}

enum MobileCredentialStoreError: Error {
    case keychain(OSStatus)
    case malformedCredential
}

final class MobileCredentialStore {
    static let shared = MobileCredentialStore()

    private let service = "com.adaptivevpn.mobile"
    private let account = "refresh-v1"

    private init() {}

    func save(_ credential: MobileCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw MobileCredentialStoreError.keychain(updateStatus)
        }

        var create = query
        attributes.forEach { create[$0.key] = $0.value }
        let addStatus = SecItemAdd(create as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MobileCredentialStoreError.keychain(addStatus)
        }
    }

    func load() throws -> MobileCredential? {
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
            throw MobileCredentialStoreError.keychain(status)
        }
        guard
            let data = result as? Data,
            let credential = try? JSONDecoder().decode(MobileCredential.self, from: data)
        else {
            throw MobileCredentialStoreError.malformedCredential
        }
        return credential
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw MobileCredentialStoreError.keychain(status)
        }
    }
}
