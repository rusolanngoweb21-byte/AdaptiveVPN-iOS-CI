import Foundation
import NetworkExtension

enum XrayTunnelManagerError: Error, Equatable {
    case runtimeGateClosed
    case invalidBootstrap
    case managerUnavailable
}

@MainActor
final class XrayTunnelManager {
    static let shared = XrayTunnelManager()

    static let runtimeActivationEnabled = false
    static let providerBundleIdentifier = "com.adaptivevpn.app.xray-tunnel"

    private init() {}

    func makeRuntimeRequest(bootstrap: VpnBootstrap) throws -> XrayRuntimeRequest {
        guard bootstrap.available, bootstrap.killSwitchRequired else {
            throw XrayTunnelManagerError.invalidBootstrap
        }
        guard let transport = bootstrap.transports?.first(where: {
            $0.kind == "vless-reality" &&
                $0.profile == "vless-reality-vision-raw-v1"
        }) else {
            throw XrayTunnelManagerError.invalidBootstrap
        }

        guard
            let clientId = transport.clientId,
            let serverName = transport.serverName,
            let shortId = transport.shortId,
            let fingerprint = transport.fingerprint,
            let flow = transport.flow,
            let network = transport.network
        else {
            throw XrayTunnelManagerError.invalidBootstrap
        }

        let clientAddress =
            transport.clientAddress?.isEmpty == false
                ? transport.clientAddress
                : bootstrap.clientAddress
        let dnsServers =
            (transport.dnsServers?.isEmpty == false)
                ? transport.dnsServers
                : bootstrap.dnsServers
        let mtu = transport.mtu ?? bootstrap.mtu

        guard
            let clientAddress,
            let dnsServers,
            !dnsServers.isEmpty,
            let mtu
        else {
            throw XrayTunnelManagerError.invalidBootstrap
        }

        do {
            return try XrayRuntimeRequest(
                clientAddress: clientAddress,
                dnsServers: dnsServers,
                mtu: mtu,
                transport: XrayRealityTransport(
                    kind: transport.kind,
                    profile: transport.profile ?? "",
                    endpointHost: transport.endpointHost,
                    endpointPort: transport.endpointPort,
                    publicKey: transport.publicKey,
                    clientId: clientId,
                    serverName: serverName,
                    shortId: shortId,
                    fingerprint: fingerprint,
                    flow: flow,
                    network: network
                )
            )
        } catch {
            throw XrayTunnelManagerError.invalidBootstrap
        }
    }

    func installConfiguration(
        bootstrap: VpnBootstrap,
        enableOnDemand: Bool = false
    ) async throws -> NETunnelProviderManager {
        guard Self.runtimeActivationEnabled else {
            throw XrayTunnelManagerError.runtimeGateClosed
        }

        let request = try makeRuntimeRequest(bootstrap: bootstrap)
        let encodedRequest = try request.encodedJSONString()

        let managers = try await loadManagers()
        let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == Self.providerBundleIdentifier
        }) ?? NETunnelProviderManager()

        let provider = NETunnelProviderProtocol()
        provider.providerBundleIdentifier = Self.providerBundleIdentifier
        provider.serverAddress =
            "\(request.transport.endpointHost):\(request.transport.endpointPort)"
        provider.includeAllNetworks = request.killSwitchRequired
        provider.excludeLocalNetworks = false
        provider.providerConfiguration = [
            "schemaVersion": XrayRuntimeRequest.schemaVersionCurrent,
            "runtimeRequest": encodedRequest
        ]

        manager.localizedDescription = "AdaptiveVPN REALITY"
        manager.protocolConfiguration = provider
        manager.isEnabled = true
        manager.isOnDemandEnabled = enableOnDemand
        manager.onDemandRules = enableOnDemand ? [NEOnDemandRuleConnect()] : []

        try await save(manager)
        try await load(manager)
        return manager
    }

    func connect(bootstrap: VpnBootstrap) async throws {
        guard Self.runtimeActivationEnabled else {
            throw XrayTunnelManagerError.runtimeGateClosed
        }

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
                .providerBundleIdentifier == Self.providerBundleIdentifier
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
                throw XrayTunnelManagerError.managerUnavailable
            case .disconnected, .connecting, .reasserting, .disconnecting:
                break
            @unknown default:
                break
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw XrayTunnelManagerError.managerUnavailable
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
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
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
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
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
