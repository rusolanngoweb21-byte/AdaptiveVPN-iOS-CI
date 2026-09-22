import XCTest
@testable import AdaptiveVPN

final class SecurityContractTests: XCTestCase {
    func testControlAPIUsesHTTPS() {
        XCTAssertEqual(APIClient.baseURL.scheme, "https")
    }

    func testBootstrapReasonSurvivesNon2xxDecoding() {
        XCTAssertEqual(
            resolveAPIErrorCode(error: nil, reason: "vpn_public_key_conflict"),
            "vpn_public_key_conflict"
        )
    }

    func testExplicitErrorTakesPrecedenceOverReason() {
        XCTAssertEqual(
            resolveAPIErrorCode(
                error: "authentication_required",
                reason: "vpn_public_key_conflict"
            ),
            "authentication_required"
        )
    }

    func testMissingStructuredCodeFallsBackSafely() {
        XCTAssertEqual(
            resolveAPIErrorCode(error: nil, reason: nil),
            "request_failed"
        )
    }
}
