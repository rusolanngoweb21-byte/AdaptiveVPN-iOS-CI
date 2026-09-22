import Foundation

enum WireGuardConfigurationError: Error {
    case unavailableBootstrap
    case incompleteBootstrap
    case wrongTransport
}

enum WireGuardConfiguration {
    static let privateKeyPlaceholder = "__ADAPTIVEVPN_PRIVATE_KEY__"

    static func providerTemplate(
        bootstrap: VpnBootstrap
    ) throws -> String {
        guard bootstrap.available else {
            throw WireGuardConfigurationError.unavailableBootstrap
        }
        guard
            let node = bootstrap.node,
            let address = bootstrap.clientAddress,
            let dns = bootstrap.dnsServers,
            !dns.isEmpty,
            let mtu = bootstrap.mtu
        else {
            throw WireGuardConfigurationError.incompleteBootstrap
        }
        guard node.transport == "wireguard" else {
            throw WireGuardConfigurationError.wrongTransport
        }

        return """
        [Interface]
        PrivateKey = (privateKeyPlaceholder)
        Address = (address)
        DNS = (dns.joined(separator: ", "))
        MTU = (mtu)

        [Peer]
        PublicKey = (node.publicKey)
        Endpoint = (node.endpointHost):(node.endpointPort)
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25
        """
    }

    static func wgQuickText(
        keyMaterial: WireGuardKeyMaterial,
        bootstrap: VpnBootstrap
    ) throws -> String {
        try providerTemplate(bootstrap: bootstrap)
            .replacingOccurrences(
                of: privateKeyPlaceholder,
                with: keyMaterial.privateKeyBase64
            )
    }
}
