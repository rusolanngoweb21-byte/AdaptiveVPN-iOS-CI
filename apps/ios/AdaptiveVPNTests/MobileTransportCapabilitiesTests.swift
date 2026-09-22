import XCTest
@testable import AdaptiveVPN

final class MobileTransportCapabilitiesTests: XCTestCase {
    func testCurrentBuildAdvertisesOnlyWireGuard() {
        XCTAssertEqual(
            MobileTransportCapabilities.supportedProfiles,
            ["wireguard-v1"]
        )
        XCTAssertFalse(
            MobileTransportCapabilities.supportedProfiles.contains(
                "vless-reality-vision-raw-v1"
            )
        )
    }
}
