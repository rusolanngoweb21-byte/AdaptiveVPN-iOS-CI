import CryptoKit
import XCTest
@testable import AdaptiveVPN

final class WireGuardConfigurationTests: XCTestCase {
    func testBuildsFullTunnelConfiguration() throws {
        let clientPrivate = Curve25519.KeyAgreement.PrivateKey()
        let serverPrivate = Curve25519.KeyAgreement.PrivateKey()
        let material = WireGuardKeyMaterial(
            privateKeyBase64: clientPrivate.rawRepresentation.base64EncodedString(),
            publicKeyBase64: clientPrivate.publicKey.rawRepresentation.base64EncodedString()
        )
        let bootstrap = VpnBootstrap(
            available: true,
            reason: nil,
            node: BootstrapNode(
                id: "11111111-1111-4111-8111-111111111111",
                region: "de-fra",
                transport: "wireguard",
                endpointHost: "203.0.113.10",
                endpointPort: 51820,
                publicKey: serverPrivate.publicKey.rawRepresentation.base64EncodedString()
            ),
            clientAddress: "10.77.1.2/32",
            dnsServers: ["1.1.1.1", "1.0.0.1"],
            mtu: 1420,
            reconnect: BootstrapReconnect(
                initialDelayMs: 500,
                maxDelayMs: 30_000,
                multiplier: 2,
                jitterRatio: 0.2
            ),
            killSwitchRequired: true
        )

        let text = try WireGuardConfiguration.wgQuickText(
            keyMaterial: material,
            bootstrap: bootstrap
        )

        XCTAssertTrue(text.contains("AllowedIPs = 0.0.0.0/0, ::/0"))
        XCTAssertTrue(text.contains("PersistentKeepalive = 25"))
        XCTAssertTrue(text.contains("Address = 10.77.1.2/32"))
    }
}
