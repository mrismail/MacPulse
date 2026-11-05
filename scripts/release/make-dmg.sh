#!/bin/bash
# Packs build/release/export/MacPulse.app into build/release/MacPulse-<version>.dmg with a
# link to /Applications, and signs the DMG when MACPULSE_TEAM_ID is set.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=build/release
APP="$OUT/export/MacPulse.app"
[ -d "$APP" ] || { echo "Run scripts/release/build-release.sh first" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/MacPulse-$VERSION.dmg"

STAGE="$OUT/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MacPulse.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MacPulse $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${MACPULSE_TEAM_ID:-}" ]; then
  codesign --sign "$(scripts/release/signing-identity.sh | cut -f1)" --timestamp "$DMG"
fi

# Check what users will get: the DMG mounts and holds a valid, signed app.
MOUNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT
codesign --verify --deep --strict "$MOUNT/MacPulse.app"
[ -L "$MOUNT/Applications" ]
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Created $DMG"
