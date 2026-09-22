import Foundation

struct PublicStatus: Decodable {
    let environment: String
    let payments: String
    let vpnNodes: String
}

struct BootstrapNode: Decodable, Equatable {
    let id: String
    let region: String
    let transport: String
    let endpointHost: String
    let endpointPort: Int
    let publicKey: String
}

struct BootstrapReconnect: Decodable, Equatable {
    let initialDelayMs: Double
    let maxDelayMs: Double
    let multiplier: Double
    let jitterRatio: Double
}

struct BootstrapTransport: Decodable, Equatable {
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
}

struct BootstrapTransportPolicy: Decodable, Equatable {
    let version: Int
    let orderedProfiles: [String]
    let connectTimeoutMs: Double
    let failureThreshold: Int
    let cooldownMs: Double
    let preferLastSuccessful: Bool
}

struct VpnBootstrap: Decodable, Equatable {
    let available: Bool
    let reason: String?
    let node: BootstrapNode?
    var transports: [BootstrapTransport]? = nil
    var transportPolicy: BootstrapTransportPolicy? = nil
    let clientAddress: String?
    let dnsServers: [String]?
    let mtu: Int?
    let reconnect: BootstrapReconnect
    let killSwitchRequired: Bool
}

struct MobilePairStart: Decodable, Equatable {
    let pairingId: String
    let userCode: String
    let pollToken: String
    let challenge: String
    let expiresIn: Int
}

struct MobileSession: Decodable, Equatable {
    let accessToken: String
    let expiresIn: Int
}

enum MobilePairCompletion: Equatable {
    case pending(retryAfterSeconds: Int)
    case paired(deviceId: String, refreshToken: String, session: MobileSession)
}

enum APIClientError: Error, Equatable {
    case invalidBaseURL
    case invalidResponse
    case api(status: Int, code: String)
}

private struct APIErrorBody: Decodable {
    let error: String?
    let reason: String?
}

func resolveAPIErrorCode(error: String?, reason: String?) -> String {
    if let error, !error.isEmpty { return error }
    if let reason, !reason.isEmpty { return reason }
    return "request_failed"
}

private struct MobilePairPendingBody: Decodable {
    let status: String
    let retryAfterSeconds: Int
}

private struct MobilePairCompleteBody: Decodable {
    struct Device: Decodable {
        let id: String
    }

    let paired: Bool
    let device: Device
    let session: MobileSession
    let refreshToken: String
}

private struct MobileRefreshBody: Decodable {
    let session: MobileSession
    let refreshToken: String
}

struct APIClient {
    static var baseURL: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "ADAPTIVEVPN_API_URL") as? String,
            let url = URL(string: raw),
            url.scheme == "https"
        else {
            preconditionFailure("AdaptiveVPN API URL must be HTTPS")
        }
        return url
    }

    func fetchStatus() async throws -> PublicStatus {
        var request = URLRequest(url: Self.baseURL.appending(path: "v1/status"))
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(request, as: PublicStatus.self)
    }

    func startMobilePairing(
        devicePublicKey: String,
        label: String?
    ) async throws -> MobilePairStart {
        var request = URLRequest(url: Self.baseURL.appending(path: "v1/mobile/pair/start"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: String] = [
            "platform": "ios",
            "devicePublicKey": devicePublicKey
        ]
        if let label, !label.isEmpty {
            payload["label"] = label
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await execute(request, as: MobilePairStart.self)
    }

    func completeMobilePairing(
        pairingId: String,
        pollToken: String,
        signature: String
    ) async throws -> MobilePairCompletion {
        var request = URLRequest(url: Self.baseURL.appending(path: "v1/mobile/pair/complete"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "pairingId": pairingId,
            "pollToken": pollToken,
            "signature": signature
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if http.statusCode == 202 {
            let pending = try JSONDecoder().decode(MobilePairPendingBody.self, from: data)
            return .pending(retryAfterSeconds: pending.retryAfterSeconds)
        }

        guard (200...299).contains(http.statusCode) else {
            throw decodeAPIError(data: data, status: http.statusCode)
        }

        let paired = try JSONDecoder().decode(MobilePairCompleteBody.self, from: data)
        return .paired(
            deviceId: paired.device.id,
            refreshToken: paired.refreshToken,
            session: paired.session
        )
    }

    func refreshMobileSession(
        credential: MobileCredential
    ) async throws -> (session: MobileSession, credential: MobileCredential) {
        var request = URLRequest(url: Self.baseURL.appending(path: "v1/mobile/session/refresh"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "deviceId": credential.deviceId,
            "refreshToken": credential.refreshToken
        ])

        let body = try await execute(request, as: MobileRefreshBody.self)
        return (
            body.session,
            MobileCredential(
                deviceId: credential.deviceId,
                refreshToken: body.refreshToken
            )
        )
    }

    func fetchVpnBootstrap(
        accessToken: String,
        deviceId: String,
        vpnPublicKey: String,
        preferredRegion: String? = nil
    ) async throws -> VpnBootstrap {
        let url = Self.baseURL.appending(path: "v1/vpn/bootstrap")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = [
            "deviceId": deviceId,
            "vpnPublicKey": vpnPublicKey,
            "supportedProfiles": MobileTransportCapabilities.supportedProfiles
        ]
        if let preferredRegion, !preferredRegion.isEmpty {
            payload["preferredRegion"] = preferredRegion
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await execute(request, as: VpnBootstrap.self)
    }

    func reportVpnStatus(
        accessToken: String,
        state: String,
        nodeId: String? = nil,
        transport: String? = nil,
        latencyMs: Int? = nil
    ) async throws {
        let url = Self.baseURL.appending(path: "v1/mobile/vpn/status")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = ["state": state]
        if let nodeId { payload["nodeId"] = nodeId }
        if let transport { payload["transport"] = transport }
        if let latencyMs { payload["latencyMs"] = latencyMs }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.api(status: http.statusCode, code: "vpn_status_report_failed")
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw decodeAPIError(data: data, status: http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func decodeAPIError(data: Data, status: Int) -> APIClientError {
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        let code = resolveAPIErrorCode(error: body?.error, reason: body?.reason)
        return .api(status: status, code: code)
    }
}
