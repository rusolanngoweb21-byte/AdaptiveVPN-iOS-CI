#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/libxray.lock"

fail() {
  echo "libXray Apple preparation failed: $*" >&2
  exit 1
}

[[ "$LIBXRAY_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid pinned version"
[[ "$LIBXRAY_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "invalid pinned commit"
[[ "$LIBXRAY_APPLE_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "invalid Apple archive digest"

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required for XCFramework validation"

if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  default_cache="${XDG_CACHE_HOME}/adaptivevpn/libxray"
elif [[ -n "${HOME:-}" ]]; then
  default_cache="${HOME}/.cache/adaptivevpn/libxray"
else
  default_cache="/tmp/adaptivevpn-libxray-${UID}"
fi
CACHE_DIR="${LIBXRAY_CACHE_DIR:-$default_cache}"
mkdir -p "$CACHE_DIR"
archive="$CACHE_DIR/${LIBXRAY_VERSION}-${LIBXRAY_APPLE_ARCHIVE}"
url="https://github.com/XTLS/libXray/releases/download/${LIBXRAY_VERSION}/${LIBXRAY_APPLE_ARCHIVE}"

verify_archive() {
  printf '%s  %s\n' "$LIBXRAY_APPLE_SHA256" "$archive" | sha256sum -c - >/dev/null 2>&1
}

if [[ -f "$archive" ]] && ! verify_archive; then
  rm -f "$archive"
fi

if [[ ! -f "$archive" ]]; then
  tmp_archive="${archive}.tmp.$$"
  trap 'rm -f "$tmp_archive"' EXIT
  curl --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors -fsSL "$url" -o "$tmp_archive"
  printf '%s  %s\n' "$LIBXRAY_APPLE_SHA256" "$tmp_archive" | sha256sum -c - >/dev/null
  mv "$tmp_archive" "$archive"
  trap - EXIT
fi

verify_archive || fail "cached archive digest mismatch"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
unzip -q "$archive" -d "$work"

source_framework="$work/libxray-apple-cgo/LibXray.xcframework"
[[ -d "$source_framework" ]] || fail "verified archive does not contain libxray-apple-cgo/LibXray.xcframework"
find "$source_framework" -name module.modulemap -type f -print -quit | grep -q . || \
  fail "LibXray.xcframework has no module.modulemap"
header="$(find "$source_framework" -name libXray.h -type f -print -quit)"
[[ -n "$header" && -f "$header" ]] || fail "LibXray.xcframework has no libXray.h"
grep -Fq 'CGoInvoke' "$header" || fail "LibXray.xcframework header has no CGoInvoke"
grep -Fq 'CGoFree' "$header" || fail "LibXray.xcframework header has no CGoFree"

python3 - "$source_framework" <<'PY'
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
info = root / "Info.plist"
if not info.is_file():
    raise SystemExit("LibXray.xcframework has no Info.plist")

with info.open("rb") as fh:
    data = plistlib.load(fh)

libraries = data.get("AvailableLibraries")
if not isinstance(libraries, list) or not libraries:
    raise SystemExit("LibXray.xcframework has no AvailableLibraries")

device_ok = False
simulator_ok = False

for item in libraries:
    if not isinstance(item, dict):
        continue
    identifier = item.get("LibraryIdentifier")
    library_path = item.get("LibraryPath")
    headers_path = item.get("HeadersPath")
    platform = item.get("SupportedPlatform")
    variant = item.get("SupportedPlatformVariant")
    architectures = set(item.get("SupportedArchitectures") or [])

    if not isinstance(identifier, str) or not isinstance(library_path, str):
        raise SystemExit("LibXray.xcframework contains an invalid library descriptor")

    slice_root = root / identifier
    if not (slice_root / library_path).is_file():
        raise SystemExit(f"missing XCFramework library payload for {identifier}")

    if isinstance(headers_path, str):
        header = slice_root / headers_path / "libXray.h"
        if not header.is_file():
            raise SystemExit(f"missing libXray.h for {identifier}")
        header_text = header.read_text(encoding="utf-8", errors="strict")
        if "CGoInvoke" not in header_text or "CGoFree" not in header_text:
            raise SystemExit(f"missing C bridge symbols in {identifier}")

    if platform == "ios" and variant is None and "arm64" in architectures:
        device_ok = True
    if (
        platform == "ios"
        and variant == "simulator"
        and {"arm64", "x86_64"}.issubset(architectures)
    ):
        simulator_ok = True

if not device_ok:
    raise SystemExit("LibXray.xcframework has no iOS arm64 device slice")
if not simulator_ok:
    raise SystemExit(
        "LibXray.xcframework has no iOS simulator slice with arm64+x86_64"
    )
PY

dest="$REPO_ROOT/apps/ios/Vendor/libxray"
rm -rf "$dest"
mkdir -p "$dest"
cp -R "$source_framework" "$dest/LibXray.xcframework"

echo "Prepared libXray Apple ${LIBXRAY_VERSION} from pinned SHA-256."
