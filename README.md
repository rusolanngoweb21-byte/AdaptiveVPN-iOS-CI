# AdaptiveVPN iOS CI mirror

This repository is a **temporary public CI mirror** used only for macOS/Xcode validation of the AdaptiveVPN Stage 13 iOS client.

The mirror contains the minimum source needed to compile and test both:
- the app-level iOS client surface used by PR #37, including authenticated tunnel-status reporting;
- the WireGuard Packet Tunnel boundary;
- the isolated Xray/REALITY Packet Tunnel boundary and pinned libXray integration.

It intentionally excludes the AdaptiveVPN backend, control plane, Telegram Mini App, node-agent, production VPN configuration, production credentials, server private keys, user data, and private repository history.

The mirror uses a non-routable placeholder Control API URL. It must not contain production secrets or production server configuration.

REALITY activation remains closed. Successful CI here is only a compile/link/unit-test gate and does not authorize production activation or deployment.
