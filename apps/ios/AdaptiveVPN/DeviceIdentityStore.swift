import CryptoKit
import Foundation
import Security

enum DeviceIdentityStoreError: Error {
    case keychain(OSStatus)
    case malformedPrivateKey
    case malformedChallenge
}

final class DeviceIdentityStore {
    static let shared = DeviceIdentityStore()

    private let service = "com.adaptivevpn.device.identity"
    private let account = "p256-v1"

    private init() {}

    func publicKeySpkiBase64URL() throws -> String {
        let privateKey = try privateKey()
        let x963 = privateKey.publicKey.x963Representation
        let spkiPrefix = Data([
            0x30, 0x59,
            0x30, 0x13,
            0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00
        ])
        return (spkiPrefix + x963).base64URLEncodedString()
    }

    func signChallengeBase64URL(_ challenge: String) throws -> String {
        guard let data = Data(base64URLEncoded: challenge), data.count == 32 else {
            throw DeviceIdentityStoreError.malformedChallenge
        }
        let signature = try privateKey().signature(for: data)
        return signature.derRepresentation.base64URLEncodedString()
    }

    private func privateKey() throws -> P256.Signing.PrivateKey {
        if let stored = try read() {
            do {
                return try P256.Signing.PrivateKey(rawRepresentation: stored)
            } catch {
                throw DeviceIdentityStoreError.malformedPrivateKey
            }
        }

        let key = P256.Signing.PrivateKey()
        try store(key.rawRepresentation)
        return key
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
            throw DeviceIdentityStoreError.keychain(status)
        }
        return result as? Data
    }

    private func store(_ raw: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: raw
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityStoreError.keychain(status)
        }
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: padding)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
