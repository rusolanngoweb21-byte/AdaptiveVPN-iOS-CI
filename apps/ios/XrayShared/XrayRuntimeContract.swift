import Foundation

struct XrayRuntimeContractError: Error, Equatable {
    let code: String
}

struct XrayRealityTransport: Codable, Equatable {
    let kind: String
    let profile: String
    let endpointHost: String
    let endpointPort: Int
    let publicKey: String
    let clientId: String
    let serverName: String
    let shortId: String
    let fingerprint: String
    let flow: String
    let network: String
}

struct XrayRuntimeRequest: Codable, Equatable {
    static let schemaVersionCurrent = 1
    static let maximumEncodedBytes = 32 * 1024

    let schemaVersion: Int
    let killSwitchRequired: Bool
    let clientAddress: String
    let dnsServers: [String]
    let mtu: Int
    let transport: XrayRealityTransport

    init(
        schemaVersion: Int = XrayRuntimeRequest.schemaVersionCurrent,
        killSwitchRequired: Bool = true,
        clientAddress: String,
        dnsServers: [String],
        mtu: Int,
        transport: XrayRealityTransport
    ) throws {
        self.schemaVersion = schemaVersion
        self.killSwitchRequired = killSwitchRequired
        self.clientAddress = clientAddress
        self.dnsServers = dnsServers
        self.mtu = mtu
        self.transport = transport
        try validate()
    }

    func encodedJSONString() throws -> String {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw XrayRuntimeContractError(code: "runtime_request_too_large")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw XrayRuntimeContractError(code: "runtime_request_not_utf8")
        }
        return text
    }

    static func decode(_ raw: String) throws -> XrayRuntimeRequest {
        guard raw.utf8.count <= maximumEncodedBytes else {
            throw XrayRuntimeContractError(code: "runtime_request_too_large")
        }
        let request: XrayRuntimeRequest
        do {
            request = try JSONDecoder().decode(
                XrayRuntimeRequest.self,
                from: Data(raw.utf8)
            )
        } catch let error as XrayRuntimeContractError {
            throw error
        } catch {
            throw XrayRuntimeContractError(code: "runtime_request_invalid_json")
        }
        try request.validate()
        return request
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersionCurrent else {
            throw XrayRuntimeContractError(code: "unsupported_runtime_request_schema")
        }
        guard killSwitchRequired else {
            throw XrayRuntimeContractError(code: "kill_switch_required")
        }

        let (address, prefix) = try Self.parseIPv4CIDR(clientAddress)
        guard prefix == 32, Self.isIPv4Literal(address) else {
            throw XrayRuntimeContractError(code: "ipv4_host_route_required")
        }

        guard !dnsServers.isEmpty else {
            throw XrayRuntimeContractError(code: "dns_required_for_fail_closed_runtime")
        }
        guard dnsServers.allSatisfy(Self.isIPv4Literal) else {
            throw XrayRuntimeContractError(code: "ipv4_dns_required")
        }
        guard (1280...1500).contains(mtu) else {
            throw XrayRuntimeContractError(code: "invalid_mtu")
        }

        guard transport.kind == "vless-reality" else {
            throw XrayRuntimeContractError(code: "reality_transport_required")
        }
        guard transport.profile == "vless-reality-vision-raw-v1" else {
            throw XrayRuntimeContractError(code: "unsupported_reality_profile")
        }
        guard Self.isIPv4Literal(transport.endpointHost) else {
            throw XrayRuntimeContractError(code: "reality_endpoint_must_be_ipv4")
        }
        guard (1...65535).contains(transport.endpointPort) else {
            throw XrayRuntimeContractError(code: "invalid_reality_port")
        }
        guard UUID(uuidString: transport.clientId) != nil else {
            throw XrayRuntimeContractError(code: "invalid_reality_client_id")
        }
        guard Self.isDNSName(transport.serverName) else {
            throw XrayRuntimeContractError(code: "invalid_reality_server_name")
        }
        guard transport.publicKey.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
        ) != nil else {
            throw XrayRuntimeContractError(code: "invalid_reality_public_key")
        }
        guard transport.shortId.range(
            of: #"^[0-9A-Fa-f]{16}$"#,
            options: .regularExpression
        ) != nil else {
            throw XrayRuntimeContractError(code: "invalid_reality_short_id")
        }
        guard transport.fingerprint == "chrome" else {
            throw XrayRuntimeContractError(code: "unsupported_reality_fingerprint")
        }
        guard transport.flow == "xtls-rprx-vision" else {
            throw XrayRuntimeContractError(code: "unsupported_reality_flow")
        }
        guard transport.network == "raw" else {
            throw XrayRuntimeContractError(code: "unsupported_reality_network")
        }
    }

    static func parseIPv4CIDR(_ value: String) throws -> (String, Int) {
        let pieces = value.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let prefix = Int(pieces[1]),
              (0...32).contains(prefix)
        else {
            throw XrayRuntimeContractError(code: "invalid_ipv4_cidr")
        }
        let address = String(pieces[0])
        guard isIPv4Literal(address) else {
            throw XrayRuntimeContractError(code: "invalid_ipv4_address")
        }
        return (address, prefix)
    }

    static func isIPv4Literal(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty,
                  part.count <= 3,
                  part.allSatisfy({ $0.isNumber }),
                  let number = Int(part),
                  (0...255).contains(number)
            else {
                return false
            }
            return true
        }
    }

    static func isDNSName(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 253,
              !value.hasPrefix("."),
              !value.hasSuffix(".")
        else {
            return false
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first?.isLetter == true || label.first?.isNumber == true,
                  label.last?.isLetter == true || label.last?.isNumber == true
            else {
                return false
            }
            return label.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            }
        }
    }
}
