#!/bin/bash
# Updates App/MacPulseApp/Resources/Localizable.xcstrings from the strings the Swift
# compiler extracts (every String(localized:), Text("…"), Label("…") and similar in the app
# and its packages). Release build, so Debug-only preview data isn't included.
# Translations already in the catalog are kept; strings no longer used are marked stale.
set -euo pipefail
cd "$(dirname "$0")/.."
CATALOG=App/MacPulseApp/Resources/Localizable.xcstrings
DERIVED=build-strings

xcodegen generate --quiet
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  SWIFT_EMIT_LOC_STRINGS=YES build > "$DERIVED.log" 2>&1 \
  || { grep -E "error:" "$DERIVED.log" | head -20; exit 1; }

ARGS=()
while IFS= read -r file; do ARGS+=(--stringsdata "$file"); done \
  < <(find "$DERIVED/Build/Intermediates.noindex" -name '*.stringsdata' | sort)
[ "${#ARGS[@]}" -gt 0 ] || { echo "No .stringsdata files were produced" >&2; exit 1; }
echo "Syncing $(( ${#ARGS[@]} / 2 )) .stringsdata files into $CATALOG"
xcrun xcstringstool sync "$CATALOG" "${ARGS[@]}"
python3 - "$CATALOG" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1]))
strings = catalog["strings"]
stale = [k for k, v in strings.items() if v.get("extractionState") == "stale"]
missing_ar = [k for k, v in strings.items()
              if v.get("extractionState") != "stale" and v.get("shouldTranslate", True)
              and "ar" not in v.get("localizations", {}) and k.strip()]
print(f"{len(strings)} strings, {len(stale)} stale, {len(missing_ar)} without Arabic")
PY
