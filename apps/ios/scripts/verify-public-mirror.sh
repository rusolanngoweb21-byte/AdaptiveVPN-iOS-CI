#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/project.yml"
MANAGER="$ROOT/AdaptiveVPN/XrayTunnelManager.swift"
CAPS_GATE="$MANAGER"
PROVIDER="$ROOT/XrayPacketTunnel/XrayPacketTunnelProvider.swift"
BRIDGE="$ROOT/XrayPacketTunnel/LibXrayBridge.swift"
CONFIG="$ROOT/XrayShared/XrayRealityConfigFactory.swift"
CONTRACT="$ROOT/XrayShared/XrayRuntimeContract.swift"
XRAY_INFO="$ROOT/XrayPacketTunnel/Info.plist"
XRAY_ENTITLEMENTS="$ROOT/XrayPacketTunnel/AdaptiveVPNXrayTunnel.entitlements"

fail() {
  echo "iOS Xray CI mirror validation failed: $*" >&2
  exit 1
}

for file in "$PROJECT" "$MANAGER" "$PROVIDER" "$BRIDGE" "$CONFIG" "$CONTRACT" "$XRAY_INFO" "$XRAY_ENTITLEMENTS"; do
  [[ -f "$file" ]] || fail "missing required source: $file"
done

app_section="$(sed -n '/^  AdaptiveVPN:/,/^  AdaptiveVPNXrayTunnel:/p' "$PROJECT")"
xray_section="$(sed -n '/^  AdaptiveVPNXrayTunnel:/,/^  AdaptiveVPNTests:/p' "$PROJECT")"

grep -Fq 'target: AdaptiveVPNXrayTunnel' <<<"$app_section" || fail "host app must embed Xray extension"
grep -Fq 'path: XrayPacketTunnel' <<<"$xray_section" || fail "Xray extension source boundary is missing"
grep -Fq 'path: XrayShared' <<<"$xray_section" || fail "shared Xray contract is missing"
grep -Fq 'framework: Vendor/libxray/LibXray.xcframework' <<<"$xray_section" || fail "Xray extension is not linked to pinned LibXray.xcframework"

grep -Fq 'static let runtimeActivationEnabled = false' "$CAPS_GATE" || fail "REALITY activation gate must remain closed"

for token in   'setTunnelNetworkSettings'   'NEIPv4Route.default()'   '255.255.255.255'   'findUtunFileDescriptor'   'getsockopt('   'LibXrayBridge.validateConfig'   'LibXrayBridge.start'   'LibXrayBridge.isRunning'   'LibXrayBridge.stop'   'beginStartGeneration'   'invalidateStartGenerations'   'start_cancelled'
do
  grep -Fq "$token" "$PROVIDER" || fail "provider missing runtime token: $token"
done

for token in 'CGoInvoke' 'CGoFree' 'apiVersion' 'getXrayState'; do
  grep -Fq "$token" "$BRIDGE" || fail "libXray bridge missing token: $token"
done

for token in   '"xray.tun.fd"'   '"autoOutboundsInterface": "auto"'   '"security": "reality"'   '"flow": "xtls-rprx-vision"'
do
  grep -Fq "$token" "$CONFIG" || fail "REALITY config missing token: $token"
done

for token in   'schemaVersionCurrent = 1'   'maximumEncodedBytes = 32 * 1024'   'kill_switch_required'   'ipv4_host_route_required'   'ipv4_dns_required'   'reality_endpoint_must_be_ipv4'
do
  grep -Fq "$token" "$CONTRACT" || fail "runtime contract missing token: $token"
done

if grep -R -n -E   'NODE_CONTROL_SECRET|REALITY_PRIVATE_KEY|WIREGUARD_PRIVATE_KEY|BEGIN [A-Z ]*PRIVATE KEY|github_pat_|gh[pousr]_'   "$ROOT"   --exclude='verify-public-mirror.sh'
then
  fail "forbidden secret material or secret-like token found in public mirror"
fi

echo "Public iOS Xray CI mirror source boundary passed."
