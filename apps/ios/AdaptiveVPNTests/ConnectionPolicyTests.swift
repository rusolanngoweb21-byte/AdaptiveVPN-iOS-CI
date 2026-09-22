import XCTest
@testable import AdaptiveVPN

final class ConnectionPolicyTests: XCTestCase {
    func testReconnectPolicyIsCappedAndJittered() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.delayForAttempt(0, randomUnit: 0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(policy.delayForAttempt(20, randomUnit: 0.5), 30.0, accuracy: 0.001)
        XCTAssertEqual(policy.delayForAttempt(0, randomUnit: 0.0), 0.4, accuracy: 0.001)
        XCTAssertEqual(policy.delayForAttempt(0, randomUnit: 1.0), 0.6, accuracy: 0.001)
    }

    func testKillSwitchFailsClosedUntilConnected() {
        let policy = KillSwitchPolicy()
        XCTAssertFalse(policy.shouldAllowNonTunnelTraffic(state: .disconnected))
        XCTAssertFalse(policy.shouldAllowNonTunnelTraffic(state: .connecting))
        XCTAssertTrue(policy.shouldAllowNonTunnelTraffic(state: .connected))
    }
}
