import XCTest
@testable import AdaptiveVPN

@MainActor
final class XrayTunnelManagerTests: XCTestCase {
    func testRuntimeActivationGateRemainsClosed() {
        XCTAssertFalse(XrayTunnelManager.runtimeActivationEnabled)
    }

    func testBuildsRealityRuntimeRequestWithTransportSpecificValues() throws {
        let transport = BootstrapTransport(
            kind: "vless-reality",
            profile: "vless-reality-vision-raw-v1",
            endpointHost: "203.0.113.10",
            endpointPort: 443,
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            clientId: "27848739-7e62-4138-9fd3-098a63964b6b",
            serverName: "example.com",
            shortId: "0123456789abcdef",
            fingerprint: "chrome",
            flow: "xtls-rprx-vision",
            network: "raw",
            clientAddress: "10.88.0.9/32",
            dnsServers: ["9.9.9.9"],
            mtu: 1420
        )
        let bootstrap = VpnBootstrap(
            available: true,
            reason: nil,
            node: nil,
            transports: [transport],
            transportPolicy: nil,
            clientAddress: "10.77.0.2/32",
            dnsServers: ["1.1.1.1"],
            mtu: 1380,
            reconnect: BootstrapReconnect(
                initialDelayMs: 500,
                maxDelayMs: 30_000,
                multiplier: 2,
                jitterRatio: 0.2
            ),
            killSwitchRequired: true
        )

        let request = try XrayTunnelManager.shared.makeRuntimeRequest(
            bootstrap: bootstrap
        )

        XCTAssertEqual(request.clientAddress, "10.88.0.9/32")
        XCTAssertEqual(request.dnsServers, ["9.9.9.9"])
        XCTAssertEqual(request.mtu, 1420)
        XCTAssertEqual(request.transport.profile, "vless-reality-vision-raw-v1")
    }
}
