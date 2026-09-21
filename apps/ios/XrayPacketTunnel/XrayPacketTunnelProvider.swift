import Darwin
import Foundation
import NetworkExtension

final class XrayPacketTunnelProvider: NEPacketTunnelProvider {
    private let runtimeQueue = DispatchQueue(
        label: "com.adaptivevpn.xray-tunnel.runtime"
    )
    private var runtimeStarted = false
    private let lifecycleLock = NSLock()
    private var lifecycleGeneration: UInt64 = 0

    override func startTunnel(
        options: [String: NSObject]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let generation = beginStartGeneration()

        let request: XrayRuntimeRequest
        do {
            request = try loadRuntimeRequest()
        } catch {
            completionHandler(error)
            return
        }

        let settings: NEPacketTunnelNetworkSettings
        do {
            settings = try makeNetworkSettings(request: request)
        } catch {
            completionHandler(error)
            return
        }

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(
                    XrayPacketTunnelError(code: "provider_deallocated")
                )
                return
            }
            if let error {
                completionHandler(error)
                return
            }

            self.runtimeQueue.async {
                guard self.isCurrentGeneration(generation) else {
                    completionHandler(
                        XrayPacketTunnelError(code: "start_cancelled")
                    )
                    return
                }

                do {
                    try self.startRuntime(request: request)
                    guard self.isCurrentGeneration(generation) else {
                        self.stopRuntime()
                        completionHandler(
                            XrayPacketTunnelError(code: "start_cancelled")
                        )
                        return
                    }
                    completionHandler(nil)
                } catch {
                    self.stopRuntime()
                    completionHandler(error)
                }
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        invalidateStartGenerations()
        runtimeQueue.async {
            self.stopRuntime()
            completionHandler()
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {}

    private func loadRuntimeRequest() throws -> XrayRuntimeRequest {
        guard
            let provider = protocolConfiguration as? NETunnelProviderProtocol,
            let configuration = provider.providerConfiguration,
            (configuration["schemaVersion"] as? NSNumber)?.intValue ==
                XrayRuntimeRequest.schemaVersionCurrent,
            let rawRequest = configuration["runtimeRequest"] as? String
        else {
            throw XrayPacketTunnelError(code: "runtime_request_missing")
        }

        return try XrayRuntimeRequest.decode(rawRequest)
    }

    private func makeNetworkSettings(
        request: XrayRuntimeRequest
    ) throws -> NEPacketTunnelNetworkSettings {
        try request.validate()
        let pieces = request.clientAddress.split(separator: "/")
        guard pieces.count == 2, pieces[1] == "32" else {
            throw XrayPacketTunnelError(code: "ipv4_host_route_required")
        }

        let settings = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: request.transport.endpointHost
        )
        let ipv4 = NEIPv4Settings(
            addresses: [String(pieces[0])],
            subnetMasks: ["255.255.255.255"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: request.dnsServers)
        settings.mtu = NSNumber(value: request.mtu)
        return settings
    }

    private func startRuntime(request: XrayRuntimeRequest) throws {
        stopRuntime()

        let tunFileDescriptor = try findUtunFileDescriptor()
        let configuration = try XrayRealityConfigFactory.make(
            request: request,
            tunFileDescriptor: tunFileDescriptor
        )

        try LibXrayBridge.validateConfig(configuration)
        try LibXrayBridge.start(configuration)

        guard try LibXrayBridge.isRunning() else {
            throw XrayPacketTunnelError(code: "xray_runtime_not_running")
        }
        runtimeStarted = true
    }

    private func stopRuntime() {
        // stopXray is idempotent and also clears an instance that could have
        // started immediately before a later health check failed.
        LibXrayBridge.stop()
        runtimeStarted = false
    }

    private func beginStartGeneration() -> UInt64 {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        lifecycleGeneration &+= 1
        return lifecycleGeneration
    }

    private func invalidateStartGenerations() {
        lifecycleLock.lock()
        lifecycleGeneration &+= 1
        lifecycleLock.unlock()
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return lifecycleGeneration == generation
    }

    private func findUtunFileDescriptor() throws -> Int32 {
        // Xray-core's iOS TUN implementation consumes the NetworkExtension
        // owned utun descriptor and explicitly does not close it.
        for rawFileDescriptor in 0...1024 {
            let fileDescriptor = Int32(rawFileDescriptor)
            var interfaceName = [CChar](
                repeating: 0,
                count: Int(IFNAMSIZ)
            )
            var length = socklen_t(interfaceName.count)

            let result = interfaceName.withUnsafeMutableBytes { bytes in
                getsockopt(
                    fileDescriptor,
                    2,
                    2,
                    bytes.baseAddress,
                    &length
                )
            }
            guard result == 0 else { continue }

            let name = interfaceName.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return "" }
                return String(cString: baseAddress)
            }
            if name.hasPrefix("utun") {
                return fileDescriptor
            }
        }

        throw XrayPacketTunnelError(code: "utun_file_descriptor_not_found")
    }
}

struct XrayPacketTunnelError: Error, Equatable {
    let code: String
}
