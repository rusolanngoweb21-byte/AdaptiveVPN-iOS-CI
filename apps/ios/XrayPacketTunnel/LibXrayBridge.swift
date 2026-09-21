import Foundation
import LibXray

struct LibXrayBridgeError: Error, Equatable {
    let code: String
}

enum LibXrayBridge {
    private static let apiVersion = 3
    private static let maximumResponseBytes = 1024 * 1024

    static func validateConfig(_ xrayJSON: String) throws {
        _ = try invoke(
            method: "testXray",
            payload: ["xrayJson": xrayJSON]
        )
    }

    static func start(_ xrayJSON: String) throws {
        _ = try invoke(
            method: "runXray",
            payload: ["xrayJson": xrayJSON]
        )
    }

    static func stop() {
        _ = try? invoke(method: "stopXray", payload: [:])
    }

    static func isRunning() throws -> Bool {
        let data = try invoke(method: "getXrayState", payload: [:])
        return data["running"] as? Bool ?? false
    }

    @discardableResult
    private static func invoke(
        method: String,
        payload: [String: Any]
    ) throws -> [String: Any] {
        let request: [String: Any] = [
            "apiVersion": apiVersion,
            "method": method,
            "payload": payload
        ]
        guard JSONSerialization.isValidJSONObject(request) else {
            throw LibXrayBridgeError(code: "libxray_request_invalid")
        }

        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            throw LibXrayBridgeError(code: "libxray_request_not_utf8")
        }

        let responsePointer: UnsafeMutablePointer<CChar>? =
            requestText.withCString { pointer in
                CGoInvoke(UnsafeMutablePointer(mutating: pointer))
            }
        guard let responsePointer else {
            throw LibXrayBridgeError(code: "libxray_empty_response")
        }
        defer { CGoFree(responsePointer) }

        let responseText = String(cString: responsePointer)
        guard responseText.utf8.count <= maximumResponseBytes else {
            throw LibXrayBridgeError(code: "libxray_response_too_large")
        }
        guard let responseData = responseText.data(using: .utf8),
              let response = try JSONSerialization.jsonObject(
                with: responseData
              ) as? [String: Any]
        else {
            throw LibXrayBridgeError(code: "libxray_response_invalid")
        }

        guard response["success"] as? Bool == true else {
            throw LibXrayBridgeError(code: "libxray_invoke_failed")
        }
        return response["data"] as? [String: Any] ?? [:]
    }
}
