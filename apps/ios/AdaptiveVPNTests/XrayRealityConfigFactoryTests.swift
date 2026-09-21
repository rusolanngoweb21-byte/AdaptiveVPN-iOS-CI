import XCTest
@testable import AdaptiveVPN

final class XrayRealityConfigFactoryTests: XCTestCase {
    private func request() throws -> XrayRuntimeRequest {
        try XrayRuntimeRequest(
            clientAddress: "10.77.0.2/32",
            dnsServers: ["1.1.1.1"],
            mtu: 1380,
            transport: XrayRealityTransport(
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
                network: "raw"
            )
        )
    }

    func testBuildsPinnedRealityTunConfigurationWithoutServerSecrets() throws {
        let json = try XrayRealityConfigFactory.make(
            request: try request(),
            tunFileDescriptor: 42
        )
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let env = try XCTUnwrap(object["env"] as? [String: Any])
        XCTAssertEqual(env["xray.tun.fd"] as? String, "42")

        let inbounds = try XCTUnwrap(object["inbounds"] as? [[String: Any]])
        let inbound = try XCTUnwrap(inbounds.first)
        XCTAssertEqual(inbound["protocol"] as? String, "tun")
        let tunSettings = try XCTUnwrap(inbound["settings"] as? [String: Any])
        XCTAssertEqual(tunSettings["autoOutboundsInterface"] as? String, "auto")
        XCTAssertEqual(tunSettings["mtu"] as? Int, 1380)

        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        let proxy = try XCTUnwrap(outbounds.first)
        XCTAssertEqual(proxy["protocol"] as? String, "vless")
        let stream = try XCTUnwrap(proxy["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["network"] as? String, "raw")
        XCTAssertEqual(stream["security"] as? String, "reality")

        XCTAssertFalse(json.contains("privateKey"))
        XCTAssertFalse(json.contains("NODE_CONTROL_SECRET"))
        XCTAssertFalse(json.contains("VPN_NODE_TOKEN"))
    }

    func testRejectsInvalidTunDescriptor() throws {
        XCTAssertThrowsError(
            try XrayRealityConfigFactory.make(
                request: try request(),
                tunFileDescriptor: -1
            )
        )
    }
}
