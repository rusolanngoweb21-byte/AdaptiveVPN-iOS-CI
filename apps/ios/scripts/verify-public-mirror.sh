#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/project.yml"
APP_STATE="$ROOT/AdaptiveVPN/AppState.swift"
API_CLIENT="$ROOT/AdaptiveVPN/APIClient.swift"
TUNNEL_MANAGER="$ROOT/AdaptiveVPN/TunnelManager.swift"
WG_PROVIDER="$ROOT/PacketTunnel/PacketTunnelProvider.swift"
XRAY_MANAGER="$ROOT/AdaptiveVPN/XrayTunnelManager.swift"
XRAY_PROVIDER="$ROOT/XrayPacketTunnel/XrayPacketTunnelProvider.swift"
BRIDGE="$ROOT/XrayPacketTunnel/LibXrayBridge.swift"
CONFIG="$ROOT/XrayShared/XrayRealityConfigFactory.swift"
CONTRACT="$ROOT/XrayShared/XrayRuntimeContract.swift"
INFO="$ROOT/AdaptiveVPN/Info.plist"

fail() {
  echo "iOS CI mirror validation failed: $*" >&2
  exit 1
}

for file in "$PROJECT" "$APP_STATE" "$API_CLIENT" "$TUNNEL_MANAGER" "$WG_PROVIDER" "$XRAY_MANAGER" "$XRAY_PROVIDER" "$BRIDGE" "$CONFIG" "$CONTRACT" "$INFO"; do
  [[ -f "$file" ]] || fail "missing required source: $file"
done

grep -Fq 'path: PacketTunnel' "$PROJECT" || fail "WireGuard extension source boundary is missing"
grep -Fq 'path: XrayPacketTunnel' "$PROJECT" || fail "Xray extension source boundary is missing"
grep -Fq 'package: WireGuardKit' "$PROJECT" || fail "WireGuardKit dependency is missing"
grep -Fq 'framework: Vendor/libxray/LibXray.xcframework' "$PROJECT" || fail "pinned libXray dependency is missing"

grep -Fq 'func reportVpnStatus' "$API_CLIENT" || fail "API client tunnel-status reporting is missing"
grep -Fq 'await reportVpnStatus("connected")' "$APP_STATE" || fail "connected tunnel-status reporting is missing"
grep -Fq 'statusTask' "$APP_STATE" || fail "fresh connected heartbeat task is missing"
grep -Fq 'waitForConnected' "$TUNNEL_MANAGER" || fail "real tunnel connection confirmation is missing"

grep -Fq 'static let runtimeActivationEnabled = false' "$XRAY_MANAGER" || fail "REALITY activation gate must remain closed"

provider_tokens=(
  'setTunnelNetworkSettings'
  'NEIPv4Route.default()'
  '255.255.255.255'
  'findUtunFileDescriptor'
  'getsockopt('
  'LibXrayBridge.validateConfig'
  'LibXrayBridge.start'
  'LibXrayBridge.isRunning'
  'LibXrayBridge.stop'
  'beginStartGeneration'
  'invalidateStartGenerations'
  'start_cancelled'
)
for token in "${provider_tokens[@]}"; do
  grep -Fq "$token" "$XRAY_PROVIDER" || fail "Xray provider missing runtime token: $token"
done

for token in 'CGoInvoke' 'CGoFree' 'apiVersion' 'getXrayState'; do
  grep -Fq "$token" "$BRIDGE" || fail "libXray bridge missing token: $token"
done

grep -Fq '<string>https://example.invalid</string>' "$INFO" || fail "public mirror must use the non-routable API placeholder"
if grep -R -n -E 'control-api-production|railway\.app|BEGIN [A-Z ]*PRIVATE KEY|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}' "$ROOT" --exclude='verify-public-mirror.sh'; then
  fail "production endpoint or high-confidence secret material found in public mirror"
fi

echo "Public iOS full-client CI mirror boundary passed."
