#!/usr/bin/env bash
set -euo pipefail

VERSION="2.46.0"
SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
URL="https://github.com/yonaskolb/XcodeGen/releases/download/${VERSION}/xcodegen.zip"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors -fsSL "$URL" -o "$work/xcodegen.zip"
printf '%s  %s\n' "$SHA256" "$work/xcodegen.zip" | shasum -a 256 -c -

unzip -q "$work/xcodegen.zip" -d "$work/unpacked"

binary="$(find "$work/unpacked" -type f -name xcodegen -perm +111 -print -quit)"
[[ -n "$binary" ]] || {
  echo "Pinned XcodeGen archive does not contain an executable xcodegen binary" >&2
  exit 1
}

mkdir -p "$HOME/.local/bin"
install -m 0755 "$binary" "$HOME/.local/bin/xcodegen"

"$HOME/.local/bin/xcodegen" --version | grep -Fq "$VERSION"
echo "$HOME/.local/bin" >> "$GITHUB_PATH"
echo "Installed checksum-pinned XcodeGen $VERSION."
