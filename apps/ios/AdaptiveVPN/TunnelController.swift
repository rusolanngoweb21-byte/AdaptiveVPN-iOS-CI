import Foundation

enum TunnelState: String, Equatable {
    case disconnected
    case preparing
    case connecting
    case connected
    case disconnecting
    case failed
}

protocol TunnelControlling {
    var state: TunnelState { get }
    var isAvailable: Bool { get }
    func connect() throws
    func disconnect()
}

enum TunnelControllerError: Error {
    case transportDeferred
}

struct DeferredTunnelController: TunnelControlling {
    let state: TunnelState = .disconnected
    let isAvailable = false

    func connect() throws {
        throw TunnelControllerError.transportDeferred
    }

    func disconnect() {}
}
