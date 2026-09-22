import Foundation

struct KillSwitchPolicy: Equatable {
    let enabled: Bool

    init(enabled: Bool = true) {
        self.enabled = enabled
    }

    func shouldAllowNonTunnelTraffic(state: TunnelState) -> Bool {
        if !enabled { return true }
        return state == .connected
    }
}
