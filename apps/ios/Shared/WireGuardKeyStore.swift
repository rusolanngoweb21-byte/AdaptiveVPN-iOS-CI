import CryptoKit
import Foundation
import Security

struct WireGuardKeyMaterial: Equatable {
    let privateKeyBase64: String
    let publicKeyBase64: String
}

enum WireGuardKeyStoreError: Error {
    case keychain(OSStatus)
    case malformedPrivateKey
    case missingPrivateKey
}

final class WireGuardKeyStore {
    static let shared = WireGuardKeyStore()

    private let service = "com.adaptivevpn.wireguard"
    private let account = "private-key-v1"

    private init() {}

    func getOrCreate() throws -> WireGuardKeyMaterial {
        if let stored = try read() {
            return try material(from: stored)
        }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let raw = privateKey.rawRepresentation
        try store(raw)
        return WireGuardKeyMaterial(
            privateKeyBase64: raw.base64EncodedString(),
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    func loadExisting() throws -> WireGuardKeyMaterial {
        guard let stored = try read() else {
            throw WireGuardKeyStoreError.missingPrivateKey
        }
        return try material(from: stored)
    }

    private func material(from raw: Data) throws -> WireGuardKeyMaterial {
        guard raw.count == 32 else {
            throw WireGuardKeyStoreError.malformedPrivateKey
        }

        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
            return WireGuardKeyMaterial(
                privateKeyBase64: raw.base64EncodedString(),
                publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        } catch {
            throw WireGuardKeyStoreError.malformedPrivateKey
        }
    }

    private func queryBase() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if !targetEnvironment(simulator)
        if let group = Bundle.main.object(forInfoDictionaryKey: "ADAPTIVEVPN_KEYCHAIN_GROUP") as? String,
           !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        #endif
        return query
    }

    private func read() throws -> Data? {
        var query = queryBase()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw WireGuardKeyStoreError.keychain(status)
        }
        return result as? Data
    }

    private func store(_ raw: Data) throws {
        var query = queryBase()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = raw

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WireGuardKeyStoreError.keychain(status)
        }
    }
}
