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

LOG_DIR="$(dirname "$TARGET")"
AUTH=(--key "$MACPULSE_NOTARY_KEY_PATH" --key-id "$MACPULSE_NOTARY_KEY_ID" --issuer "$MACPULSE_NOTARY_ISSUER_ID")
# A team's first submissions can take long; stop waiting after 30 minutes instead of being
# killed by the job timeout, and always show Apple's log when it isn't accepted.
set +e
xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --timeout 30m --output-format json > "$LOG_DIR/notarization.json"
SUBMIT_STATUS=$?
set -e
cat "$LOG_DIR/notarization.json"
STATUS=$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("status", ""))
except Exception: print("")' "$LOG_DIR/notarization.json")
if [ "$SUBMIT_STATUS" -ne 0 ] || [ "$STATUS" != "Accepted" ]; then
  ID=$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("id", ""))
except Exception: print("")' "$LOG_DIR/notarization.json")
  echo "Notarization status: ${STATUS:-unknown} (notarytool exit $SUBMIT_STATUS)" >&2
  if [ -n "$ID" ]; then
    xcrun notarytool log "$ID" "${AUTH[@]}" "$LOG_DIR/notarization-log.json" || true
    cat "$LOG_DIR/notarization-log.json" >&2 || true
  fi
  exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
[[ "$TARGET" == *.app ]] && rm -f "$SUBMIT"
spctl --assess --type "$([[ "$TARGET" == *.dmg ]] && echo open --context context:primary-signature || echo execute)" --verbose "$TARGET"
echo "Notarized and stapled: $TARGET"
