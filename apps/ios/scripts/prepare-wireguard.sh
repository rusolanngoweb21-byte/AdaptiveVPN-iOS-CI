#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_URL="https://git.zx2c4.com/wireguard-apple"
UPSTREAM_COMMIT="2fec12a6e1f6e3460b6ee483aa00ad29cddadab1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Vendor/wireguard-apple"

rm -rf "$DEST_DIR"
mkdir -p "$(dirname "$DEST_DIR")"

git clone --no-checkout "$UPSTREAM_URL" "$DEST_DIR"
git -C "$DEST_DIR" fetch --depth=1 origin "$UPSTREAM_COMMIT"
git -C "$DEST_DIR" checkout --detach FETCH_HEAD

ACTUAL_COMMIT="$(git -C "$DEST_DIR" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$UPSTREAM_COMMIT" ]]; then
  echo "Unexpected WireGuard upstream commit: $ACTUAL_COMMIT" >&2
  exit 1
fi

PACKAGE_FILE="$DEST_DIR/Package.swift"
if ! grep -q '^// swift-tools-version:5.3$' "$PACKAGE_FILE"; then
  echo "Unexpected WireGuard Package.swift tools version; refusing compatibility patch." >&2
  exit 1
fi

python3 - "$PACKAGE_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("// swift-tools-version:5.3\n", "// swift-tools-version:5.9\n", 1)
path.write_text(text)

header = path.parent / "Sources" / "WireGuardKitC" / "WireGuardKitC.h"
h = header.read_text()
if '#include <stdint.h>' not in h:
    marker = '#include "key.h"'
    if marker not in h:
        raise SystemExit("Unexpected WireGuardKitC.h layout")
    h = h.replace(marker, '#include <stdint.h>\n\n' + marker, 1)

replacements = {
    "u_int32_t": "uint32_t",
    "u_int16_t": "uint16_t",
    "u_char": "uint8_t",
}
for old, new in replacements.items():
    h = h.replace(old, new)
header.write_text(h)
PY

echo "Prepared official WireGuardKit at $UPSTREAM_COMMIT with Xcode 16 compatibility patches matching upstream PR #58 (Swift tools + stdint types)."
