import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("app_name")
                        .font(.system(size: 34, weight: .bold))

                    Text("mobile_shell_title")
                        .font(.title2.weight(.semibold))

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            if state.isLoading {
                                ProgressView("checking_service")
                            } else if let status = state.serviceStatus {
                                Text("API: \(status.environment)")
                                Text("Payments: \(status.payments)")
                                Text("VPN nodes: \(status.vpnNodes)")
                            } else {
                                Text(state.errorMessage ?? String(localized: "service_unavailable"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Label(
                        state.secureStorageReady
                            ? String(localized: "secure_storage_ready")
                            : String(localized: "secure_storage_failed"),
                        systemImage: state.secureStorageReady ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(state.secureStorageReady ? .green : .orange)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                state.isLinked
                                    ? String(localized: "mobile_pair_linked_title")
                                    : String(localized: "mobile_pair_title"),
                                systemImage: state.isLinked ? "checkmark.circle.fill" : "link.circle"
                            )
                            .font(.headline)

                            Text(state.pairingMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let code = state.pairingCode {
                                Text(code)
                                    .font(.system(.title2, design: .monospaced, weight: .bold))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                            }

                            if !state.isLinked {
                                Button {
                                    state.startPairing()
                                } label: {
                                    if state.isPairing {
                                        HStack {
                                            ProgressView()
                                            Text("mobile_pair_waiting")
                                        }
                                    } else {
                                        Text("mobile_pair_start")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(state.isPairing || !state.secureStorageReady)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if state.isLinked {
                        Button {
                            Task { await state.toggleVpn() }
                        } label: {
                            if state.vpnConnecting {
                                HStack {
                                    ProgressView()
                                    Text("vpn_connecting")
                                }
                            } else {
                                Text(
                                    state.vpnConnected
                                        ? String(localized: "vpn_disconnect")
                                        : String(localized: "vpn_connect")
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled((!state.vpnReady && !state.vpnConnected) || state.vpnConnecting)

                        Text("vpn_kill_switch_ios_notice")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("refresh") {
                        Task { await state.refresh() }
                    }
                    .buttonStyle(.bordered)

                    Text("phase_notice")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.10), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}
