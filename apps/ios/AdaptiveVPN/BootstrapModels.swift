import Foundation

struct BootstrapReconnect: Codable, Equatable {
    let initialDelayMs: Int
    let maxDelayMs: Int
    let multiplier: Double
    let jitterRatio: Double
}

struct BootstrapTransport: Codable, Equatable {
    let kind: String
    let profile: String?
    let endpointHost: String
    let endpointPort: Int
    let publicKey: String
    let clientId: String?
    let serverName: String?
    let shortId: String?
    let fingerprint: String?
    let flow: String?
    let network: String?
    let clientAddress: String?
    let dnsServers: [String]?
    let mtu: Int?

    init(
        kind: String,
        profile: String? = nil,
        endpointHost: String,
        endpointPort: Int,
        publicKey: String,
        clientId: String? = nil,
        serverName: String? = nil,
        shortId: String? = nil,
        fingerprint: String? = nil,
        flow: String? = nil,
        network: String? = nil,
        clientAddress: String? = nil,
        dnsServers: [String]? = nil,
        mtu: Int? = nil
    ) {
        self.kind = kind
        self.profile = profile
        self.endpointHost = endpointHost
        self.endpointPort = endpointPort
        self.publicKey = publicKey
        self.clientId = clientId
        self.serverName = serverName
        self.shortId = shortId
        self.fingerprint = fingerprint
        self.flow = flow
        self.network = network
        self.clientAddress = clientAddress
        self.dnsServers = dnsServers
        self.mtu = mtu
    }
}

struct VpnBootstrap: Codable, Equatable {
    let available: Bool
    let reason: String?
    let node: String?
    let transports: [BootstrapTransport]?
    let transportPolicy: String?
    let clientAddress: String?
    let dnsServers: [String]?
    let mtu: Int?
    let reconnect: BootstrapReconnect?
    let killSwitchRequired: Bool
}
