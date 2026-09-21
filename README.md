# AdaptiveVPN iOS CI mirror

This repository is a **temporary public CI mirror** used only to run the macOS/Xcode gate for the AdaptiveVPN Stage 13 iOS Xray/REALITY runtime.

It intentionally contains only the minimum iOS runtime boundary required for compile/link/unit-test validation:

- the isolated `AdaptiveVPNXrayTunnel` Packet Tunnel extension;
- the shared schema-versioned Xray runtime contract;
- the REALITY Xray configuration factory;
- the C bridge to the checksum-pinned official `libXray` XCFramework;
- a minimal host app and bootstrap model surface;
- focused unit tests and CI scripts.

It intentionally does **not** contain the AdaptiveVPN backend, control plane, Telegram Mini App, node-agent, production VPN configuration, production credentials, server private keys, user data, or the private repository history.

The runtime activation gate stays closed in this mirror. Successful CI here is a compile/link/test gate only; it does not authorize production REALITY activation.
