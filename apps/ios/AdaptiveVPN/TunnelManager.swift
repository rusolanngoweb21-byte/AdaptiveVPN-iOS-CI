import Foundation
import NetworkExtension

enum TunnelManagerError: Error {
    case invalidBootstrap
    case managerUnavailable
}

@MainActor
final class TunnelManager {
    static let shared = TunnelManager()

    private let providerBundleIdentifier = "com.adaptivevpn.app.tunnel"

    private init() {}

    func installConfiguration(
        bootstrap: VpnBootstrap,
        enableOnDemand: Bool = false
    ) async throws -> NETunnelProviderManager {
        guard
            bootstrap.available,
            let node = bootstrap.node,
            let clientAddress = bootstrap.clientAddress,
            let dnsServers = bootstrap.dnsServers,
            !dnsServers.isEmpty,
            let mtu = bootstrap.mtu
        else {
            throw TunnelManagerError.invalidBootstrap
        }

        let managers = try await loadManagers()
        let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == providerBundleIdentifier
        }) ?? NETunnelProviderManager()

        let provider = NETunnelProviderProtocol()
        provider.providerBundleIdentifier = providerBundleIdentifier
        provider.serverAddress = "\(node.endpointHost):\(node.endpointPort)"
        provider.includeAllNetworks = bootstrap.killSwitchRequired
        provider.excludeLocalNetworks = false
        provider.providerConfiguration = [
            "schemaVersion": 1,
            "clientAddress": clientAddress,
            "dnsServers": dnsServers,
            "mtu": mtu,
            "serverPublicKey": node.publicKey,
            "endpointHost": node.endpointHost,
            "endpointPort": node.endpointPort,
            "persistentKeepalive": 25
        ]

        manager.localizedDescription = "AdaptiveVPN"
        manager.protocolConfiguration = provider
        manager.isEnabled = true
        manager.isOnDemandEnabled = enableOnDemand
        manager.onDemandRules = enableOnDemand ? [NEOnDemandRuleConnect()] : []

        try await save(manager)
        try await load(manager)
        return manager
    }

    func connect(bootstrap: VpnBootstrap) async throws {
        let manager = try await installConfiguration(
            bootstrap: bootstrap,
            enableOnDemand: true
        )
        try manager.connection.startVPNTunnel()
        try await waitForConnected(manager.connection)
    }

    func disconnect() async throws {
        let managers = try await loadManagers()
        guard let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == providerBundleIdentifier
        }) else {
            return
        }

        manager.connection.stopVPNTunnel()
        manager.isOnDemandEnabled = false
        manager.onDemandRules = []
        try await save(manager)
    }

    private func waitForConnected(
        _ connection: NEVPNConnection,
        timeoutSeconds: Double = 20
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            switch connection.status {
            case .connected:
                return
            case .invalid:
                throw TunnelManagerError.managerUnavailable
            case .disconnected:
                break
            case .connecting, .reasserting, .disconnecting:
                break
            @unknown default:
                break
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw TunnelManagerError.managerUnavailable
    }

    private func loadManagers() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func load(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
