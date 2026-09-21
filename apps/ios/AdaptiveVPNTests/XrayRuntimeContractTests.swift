import XCTest
@testable import AdaptiveVPN

final class XrayRuntimeContractTests: XCTestCase {
    private func request(
        killSwitchRequired: Bool = true,
        clientAddress: String = "10.77.0.2/32",
        dnsServers: [String] = ["1.1.1.1", "8.8.8.8"],
        endpointHost: String = "203.0.113.10"
    ) throws -> XrayRuntimeRequest {
        try XrayRuntimeRequest(
            killSwitchRequired: killSwitchRequired,
            clientAddress: clientAddress,
            dnsServers: dnsServers,
            mtu: 1380,
            transport: XrayRealityTransport(
                kind: "vless-reality",
                profile: "vless-reality-vision-raw-v1",
                endpointHost: endpointHost,
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

    func testRoundTripsFailClosedRuntimeRequest() throws {
        let original = try request()
        let decoded = try XrayRuntimeRequest.decode(
            try original.encodedJSONString()
        )

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.killSwitchRequired)
    }

    func testRejectsMissingKillSwitchRequirement() {
        XCTAssertThrowsError(
            try request(killSwitchRequired: false)
        )
    }

    func testRejectsNonHostClientAddress() {
        XCTAssertThrowsError(
            try request(clientAddress: "10.77.0.2/24")
        )
    }

    func testRejectsIpv6DnsWhileFirstNodeIsIpv4Only() {
        XCTAssertThrowsError(
            try request(dnsServers: ["2606:4700:4700::1111"])
        )
    }

    func testRejectsDnsRealityEndpointForPinnedIpv4NodeContract() {
        XCTAssertThrowsError(
            try request(endpointHost: "vpn.example.com")
        )
    }

    func testRejectsOversizedRuntimeRequest() {
        XCTAssertThrowsError(
            try XrayRuntimeRequest.decode(
                String(repeating: "x", count: XrayRuntimeRequest.maximumEncodedBytes + 1)
            )
        )
    }
}
