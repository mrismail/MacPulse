#!/bin/bash
# Installs a pinned XcodeGen release, checked against its SHA-256, into $RUNNER_TEMP (or
# /tmp) and puts it on the PATH for the following GitHub Actions steps.
set -euo pipefail
VERSION=2.45.4
SHA256=090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef
DEST="${RUNNER_TEMP:-/tmp}/xcodegen-$VERSION"
if [ ! -x "$DEST/xcodegen/bin/xcodegen" ]; then
  mkdir -p "$DEST"
  curl -fsSL -o "$DEST/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
  echo "$SHA256  $DEST/xcodegen.zip" | shasum -a 256 -c -
  unzip -q -o "$DEST/xcodegen.zip" -d "$DEST"
fi
"$DEST/xcodegen/bin/xcodegen" --version
if [ -n "${GITHUB_PATH:-}" ]; then echo "$DEST/xcodegen/bin" >> "$GITHUB_PATH"; fi
