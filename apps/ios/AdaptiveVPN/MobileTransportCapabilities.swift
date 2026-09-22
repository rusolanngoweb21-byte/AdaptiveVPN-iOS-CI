import Foundation

enum MobileTransportCapabilities {
    static let wireGuardProfile = "wireguard-v1"

    // REALITY remains unavailable until an embedded Xray/libXray runtime is
    // present in the app build and has passed runtime/device validation.
    static let supportedProfiles = [wireGuardProfile]
}
