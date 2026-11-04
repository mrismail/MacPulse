#!/bin/bash
# Notarizes and staples a Developer ID–signed app or DMG.
#   scripts/release/notarize.sh build/release/export/MacPulse.app
#   scripts/release/notarize.sh build/release/MacPulse-1.0.0.dmg
#
# Needs an App Store Connect API key (Users and Access > Integrations > Keys):
#   MACPULSE_NOTARY_KEY_PATH  path to the AuthKey_XXXX.p8 file
#   MACPULSE_NOTARY_KEY_ID    the key ID
#   MACPULSE_NOTARY_ISSUER_ID the issuer ID
set -euo pipefail
TARGET="${1:?Usage: $0 path/to/MacPulse.app|.dmg}"
: "${MACPULSE_NOTARY_KEY_PATH:?not set}" "${MACPULSE_NOTARY_KEY_ID:?not set}" "${MACPULSE_NOTARY_ISSUER_ID:?not set}"

SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMIT="$(dirname "$TARGET")/MacPulse-notarize.zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi

xcrun notarytool submit "$SUBMIT" \
  --key "$MACPULSE_NOTARY_KEY_PATH" --key-id "$MACPULSE_NOTARY_KEY_ID" --issuer "$MACPULSE_NOTARY_ISSUER_ID" \
  --wait --output-format json | tee "$(dirname "$TARGET")/notarization.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r.get("status")=="Accepted" else 1)' \
  "$(dirname "$TARGET")/notarization.json" || {
  echo "Notarization was not accepted; fetch the log with: xcrun notarytool log <id> --key ..." >&2
  exit 1
}
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
[[ "$TARGET" == *.app ]] && rm -f "$SUBMIT"
spctl --assess --type "$([[ "$TARGET" == *.dmg ]] && echo open --context context:primary-signature || echo execute)" --verbose "$TARGET"
echo "Notarized and stapled: $TARGET"
