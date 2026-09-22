import Foundation
import NetworkExtension

#if canImport(WireGuardKit)
import WireGuardKit
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    #if canImport(WireGuardKit)
    private lazy var adapter = WireGuardAdapter(with: self) { _, _ in }
    #endif

    override func startTunnel(
        options: [String : NSObject]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        #if canImport(WireGuardKit)
        do {
            let configuration = try makeTunnelConfiguration()
            adapter.start(tunnelConfiguration: configuration) { error in
                completionHandler(error)
            }
        } catch {
            completionHandler(error)
        }
        #else
        completionHandler(
            NSError(
                domain: "com.adaptivevpn.tunnel",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "WireGuardKit is not linked"]
            )
        )
        #endif
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        #if canImport(WireGuardKit)
        adapter.stop { _ in
            completionHandler()
        }
        #else
        completionHandler()
        #endif
    }

    #if canImport(WireGuardKit)
    private func makeTunnelConfiguration() throws -> TunnelConfiguration {
        guard
            let provider = protocolConfiguration as? NETunnelProviderProtocol,
            let raw = provider.providerConfiguration,
            (raw["schemaVersion"] as? NSNumber)?.intValue == 1,
            let clientAddress = raw["clientAddress"] as? String,
            let dnsStrings = raw["dnsServers"] as? [String],
            !dnsStrings.isEmpty,
            let mtuNumber = raw["mtu"] as? NSNumber,
            let serverPublicKey = raw["serverPublicKey"] as? String,
            let endpointHost = raw["endpointHost"] as? String,
            let endpointPortNumber = raw["endpointPort"] as? NSNumber,
            let keepaliveNumber = raw["persistentKeepalive"] as? NSNumber
        else {
            throw tunnelError(1001, "Missing or invalid tunnel configuration")
        }

        let keyMaterial = try WireGuardKeyStore.shared.loadExisting()
        guard let privateKey = PrivateKey(base64Key: keyMaterial.privateKeyBase64) else {
            throw tunnelError(1003, "Invalid private key")
        }
        guard let address = IPAddressRange(from: clientAddress) else {
            throw tunnelError(1004, "Invalid client address")
        }

        let dns = dnsStrings.compactMap(DNSServer.init(from:))
        guard dns.count == dnsStrings.count else {
            throw tunnelError(1005, "Invalid DNS server")
        }

        let mtuValue = mtuNumber.intValue
        guard mtuValue >= 1280, mtuValue <= 1500 else {
            throw tunnelError(1006, "Invalid MTU")
        }

        guard let publicKey = PublicKey(base64Key: serverPublicKey) else {
            throw tunnelError(1007, "Invalid server public key")
        }

        let endpointPort = endpointPortNumber.intValue
        guard endpointPort >= 1, endpointPort <= 65535 else {
            throw tunnelError(1008, "Invalid endpoint port")
        }

        let endpointText: String
        if endpointHost.contains(":") && !endpointHost.hasPrefix("[") {
            endpointText = "[\(endpointHost)]:\(endpointPort)"
        } else {
            endpointText = "\(endpointHost):\(endpointPort)"
        }
        guard let endpoint = Endpoint(from: endpointText) else {
            throw tunnelError(1009, "Invalid endpoint")
        }

        guard
            let ipv4Default = IPAddressRange(from: "0.0.0.0/0"),
            let ipv6Default = IPAddressRange(from: "::/0")
        else {
            throw tunnelError(1010, "Could not create full-tunnel routes")
        }

        let keepalive = keepaliveNumber.intValue
        guard keepalive >= 0, keepalive <= 65535 else {
            throw tunnelError(1011, "Invalid keepalive")
        }

        var interface = InterfaceConfiguration(privateKey: privateKey)
        interface.addresses = [address]
        interface.dns = dns
        interface.mtu = UInt16(mtuValue)

        var peer = PeerConfiguration(publicKey: publicKey)
        peer.allowedIPs = [ipv4Default, ipv6Default]
        peer.endpoint = endpoint
        peer.persistentKeepAlive = UInt16(keepalive)

        return TunnelConfiguration(
            name: "AdaptiveVPN",
            interface: interface,
            peers: [peer]
        )
    }

    private func tunnelError(_ code: Int, _ message: String) -> NSError {
        NSError(
            domain: "com.adaptivevpn.tunnel",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
    #endif
}
