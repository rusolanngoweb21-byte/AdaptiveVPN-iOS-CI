import Foundation
import UIKit

@MainActor
final class AppState: ObservableObject {
    @Published var serviceStatus: PublicStatus?
    @Published var errorMessage: String?
    @Published var secureStorageReady = false
    @Published var isLoading = false

    @Published var isPairing = false
    @Published var isLinked = false
    @Published var pairingCode: String?
    @Published var pairingMessage = String(localized: "mobile_pair_not_linked")
    @Published var vpnReady = false
    @Published var vpnConnecting = false
    @Published var vpnConnected = false

    private var latestBootstrap: VpnBootstrap?
    private var mobileSession: MobileSession?
    private var currentDeviceId: String?

    private let api = APIClient()
    private var pairingTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    deinit {
        pairingTask?.cancel()
        statusTask?.cancel()
    }

    func bootstrap() async {
        do {
            _ = try SecureInstallationSecret.shared.getOrCreate()
            _ = try WireGuardKeyStore.shared.getOrCreate()
            _ = try DeviceIdentityStore.shared.publicKeySpkiBase64URL()
            secureStorageReady = true
        } catch {
            secureStorageReady = false
            errorMessage = String(localized: "secure_storage_failed")
        }

        await refresh()
        await restoreMobileSession()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            serviceStatus = try await api.fetchStatus()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "service_unavailable")
        }
    }

    func startPairing() {
        guard !isPairing else { return }
        pairingTask?.cancel()
        pairingTask = Task { [weak self] in
            guard let self else { return }
            await self.runPairing()
        }
    }

    private func runPairing() async {
        isPairing = true
        pairingCode = nil
        pairingMessage = String(localized: "mobile_pair_starting")
        defer { isPairing = false }

        do {
            let publicKey = try DeviceIdentityStore.shared.publicKeySpkiBase64URL()
            let pairing = try await api.startMobilePairing(
                devicePublicKey: publicKey,
                label: UIDevice.current.model
            )

            let signature = try DeviceIdentityStore.shared.signChallengeBase64URL(
                pairing.challenge
            )
            pairingCode = pairing.userCode
            pairingMessage = format(
                key: "mobile_pair_code",
                value: pairing.userCode
            )

            let deadline = Date().addingTimeInterval(TimeInterval(pairing.expiresIn))

            while Date() < deadline && !Task.isCancelled {
                let result = try await api.completeMobilePairing(
                    pairingId: pairing.pairingId,
                    pollToken: pairing.pollToken,
                    signature: signature
                )

                switch result {
                case .pending(let retryAfterSeconds):
                    pairingMessage = format(
                        key: "mobile_pair_code",
                        value: pairing.userCode
                    )
                    let delay = UInt64(max(1, min(10, retryAfterSeconds))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)

                case .paired(let deviceId, let refreshToken, let session):
                    let credential = MobileCredential(
                        deviceId: deviceId,
                        refreshToken: refreshToken
                    )
                    try MobileCredentialStore.shared.save(credential)
                    mobileSession = session
                    currentDeviceId = deviceId
                    pairingCode = nil
                    isLinked = true
                    pairingMessage = String(localized: "mobile_pair_linked")
                    await checkVpnReadiness(
                        deviceId: deviceId,
                        session: session
                    )
                    return
                }
            }

            if !Task.isCancelled {
                pairingCode = nil
                pairingMessage = String(localized: "mobile_pair_expired")
            }
        } catch let error as APIClientError {
            pairingCode = nil
            switch error {
            case .api(_, let code) where code == "mobile_pairing_expired":
                pairingMessage = String(localized: "mobile_pair_expired")
            default:
                pairingMessage = String(localized: "mobile_pair_error")
            }
        } catch is CancellationError {
            return
        } catch {
            pairingCode = nil
            pairingMessage = String(localized: "mobile_pair_error")
        }
    }

    private func restoreMobileSession() async {
        do {
            guard let credential = try MobileCredentialStore.shared.load() else {
                isLinked = false
                pairingMessage = String(localized: "mobile_pair_not_linked")
                return
            }

            pairingMessage = String(localized: "mobile_pair_restoring")
            let refreshed = try await api.refreshMobileSession(credential: credential)
            try MobileCredentialStore.shared.save(refreshed.credential)
            mobileSession = refreshed.session
            currentDeviceId = refreshed.credential.deviceId
            isLinked = true
            pairingMessage = String(localized: "mobile_pair_linked")
            await checkVpnReadiness(
                deviceId: refreshed.credential.deviceId,
                session: refreshed.session
            )
        } catch {
            try? MobileCredentialStore.shared.clear()
            mobileSession = nil
            currentDeviceId = nil
            statusTask?.cancel()
            isLinked = false
            pairingMessage = String(localized: "mobile_pair_not_linked")
        }
    }

    private func checkVpnReadiness(
        deviceId: String,
        session: MobileSession
    ) async {
        do {
            let vpnKey = try WireGuardKeyStore.shared.getOrCreate()
            let bootstrap = try await api.fetchVpnBootstrap(
                accessToken: session.accessToken,
                deviceId: deviceId,
                vpnPublicKey: vpnKey.publicKeyBase64
            )

            latestBootstrap = bootstrap.available ? bootstrap : nil
            vpnReady = bootstrap.available
            if bootstrap.available {
                pairingMessage = String(localized: "vpn_ready_for_connection")
            } else {
                pairingMessage = format(
                    key: "vpn_waiting_reason",
                    value: bootstrap.reason ?? "not-provisioned"
                )
            }
        } catch {
            // Pairing is still valid even if VPN bootstrap is unavailable.
        }
    }


    private func reportVpnStatus(_ state: String) async {
        guard let session = mobileSession else { return }

        let requiresAssignment = state == "connecting" || state == "connected" || state == "reconnecting"
        let nodeId = requiresAssignment ? latestBootstrap?.node?.id : nil
        let transport = requiresAssignment
            ? latestBootstrap?.transports?.first(where: { $0.kind == "wireguard" })?.kind
            : nil

        if requiresAssignment && (nodeId == nil || transport == nil) {
            return
        }

        try? await api.reportVpnStatus(
            accessToken: session.accessToken,
            state: state,
            nodeId: nodeId,
            transport: transport
        )
    }

    private func startTunnelStatusHeartbeat() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.vpnConnected else { return }

                switch await TunnelManager.shared.runtimeState() {
                case .connected:
                    await self.reportVpnStatus("connected")
                case .connecting:
                    await self.reportVpnStatus("connecting")
                case .reconnecting:
                    await self.reportVpnStatus("reconnecting")
                case .disconnected:
                    self.vpnConnected = false
                    await self.reportVpnStatus("disconnected")
                    return
                case .error:
                    self.vpnConnected = false
                    await self.reportVpnStatus("error")
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func toggleVpn() async {
        if vpnConnected {
            await disconnectVpn()
        } else {
            await connectVpn()
        }
    }

    private func connectVpn() async {
        guard let bootstrap = latestBootstrap, bootstrap.available else { return }
        guard !vpnConnecting else { return }

        vpnConnecting = true
        pairingMessage = String(localized: "vpn_connecting")
        defer { vpnConnecting = false }

        await reportVpnStatus("connecting")
        do {
            try await TunnelManager.shared.connect(bootstrap: bootstrap)
            vpnConnected = true
            pairingMessage = String(localized: "vpn_connected")
            await reportVpnStatus("connected")
            startTunnelStatusHeartbeat()
        } catch {
            statusTask?.cancel()
            vpnConnected = false
            pairingMessage = String(localized: "vpn_connect_error")
            await reportVpnStatus("error")
        }
    }

    private func disconnectVpn() async {
        vpnConnecting = true
        statusTask?.cancel()
        defer { vpnConnecting = false }

        do {
            try await TunnelManager.shared.disconnect()
            vpnConnected = false
            pairingMessage = String(localized: "vpn_disconnected")
            await reportVpnStatus("disconnected")
        } catch {
            pairingMessage = String(localized: "vpn_disconnect_error")
            await reportVpnStatus("error")
        }
    }

    private func format(key: String, value: String) -> String {
        String(
            format: NSLocalizedString(key, comment: ""),
            locale: Locale.current,
            value
        )
    }
}
