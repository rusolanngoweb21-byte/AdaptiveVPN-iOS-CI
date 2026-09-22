#!/usr/bin/env bash
set -euo pipefail

EXPECTED_COMMIT="2fec12a6e1f6e3460b6ee483aa00ad29cddadab1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Vendor/wireguard-apple"

test -d "$SOURCE_DIR/.git"
test "$(git -C "$SOURCE_DIR" rev-parse HEAD)" = "$EXPECTED_COMMIT"
grep -q '^// swift-tools-version:5.9$' "$SOURCE_DIR/Package.swift"
test -f "$SOURCE_DIR/Sources/WireGuardKitGo/Makefile"
test -f "$SOURCE_DIR/COPYING"
grep -q '#include <stdint.h>' "$SOURCE_DIR/Sources/WireGuardKitC/WireGuardKitC.h"
! grep -Eq '\bu_int(16|32)_t\b|\bu_char\b' "$SOURCE_DIR/Sources/WireGuardKitC/WireGuardKitC.h"

echo "WireGuardKit source pin verified."
