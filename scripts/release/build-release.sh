#!/bin/bash
# Archives and exports MacPulse.app for release into build/release/export/MacPulse.app.
#
# Signing:
#   - MACPULSE_TEAM_ID set: Developer ID Application certificate (must be in the keychain),
#     Hardened Runtime and a secure timestamp, as notarization requires.
#   - otherwise: ad-hoc signing ("-"). The app runs, but Gatekeeper asks users to confirm
#     the first launch (right-click > Open). See Documentation/RELEASE.md.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=build/release
rm -rf "$OUT"
mkdir -p "$OUT"
BUILD_NUMBER="$(git rev-list --count HEAD)"

command -v xcodegen >/dev/null || { echo "xcodegen is required (brew install xcodegen)" >&2; exit 1; }
xcodegen generate --quiet

SIGNING=(CODE_SIGN_STYLE=Manual)
if [ -n "${MACPULSE_TEAM_ID:-}" ]; then
  echo "Signing with Developer ID (team $MACPULSE_TEAM_ID)"
  SIGNING+=(DEVELOPMENT_TEAM="$MACPULSE_TEAM_ID" "CODE_SIGN_IDENTITY=Developer ID Application" "OTHER_CODE_SIGN_FLAGS=--timestamp")
else
  echo "MACPULSE_TEAM_ID not set: ad-hoc signing (not notarizable)"
  SIGNING+=(DEVELOPMENT_TEAM= "CODE_SIGN_IDENTITY=-")
fi

set -o pipefail
xcodebuild archive \
  -project MacPulse.xcodeproj -scheme MacPulse -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$OUT/MacPulse.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  "${SIGNING[@]}" 2>&1 | tee "$OUT/archive.log" | grep -E "error:|warning:|\*\* ARCHIVE" || true
grep -q "\*\* ARCHIVE SUCCEEDED \*\*" "$OUT/archive.log" || { echo "Archive failed (see $OUT/archive.log)" >&2; exit 1; }

mkdir -p "$OUT/export"
if [ -n "${MACPULSE_TEAM_ID:-}" ]; then
  cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>${MACPULSE_TEAM_ID}</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$OUT/MacPulse.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"
else
  # Ad-hoc builds can't use the developer-id export method; the archived app is the product.
  ditto "$OUT/MacPulse.xcarchive/Products/Applications/MacPulse.app" "$OUT/export/MacPulse.app"
fi

APP="$OUT/export/MacPulse.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -Eq "flags=.*runtime" || { echo "Hardened Runtime missing" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "Built MacPulse $VERSION ($BUILD_NUMBER) at $APP"
echo "$VERSION" > "$OUT/VERSION"
