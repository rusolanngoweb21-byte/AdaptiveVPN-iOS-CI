import XCTest
@testable import AdaptiveVPN

final class TunnelControllerTests: XCTestCase {
    func testTunnelRemainsDisabledUntilPhaseFive() {
        let controller = DeferredTunnelController()
        XCTAssertFalse(controller.isAvailable)
        XCTAssertThrowsError(try controller.connect())
    }
}
