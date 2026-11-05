#!/bin/bash
# Prints the one Developer ID Application identity for MACPULSE_TEAM_ID as
# "<SHA-1>\t<full name>", or fails when there is none or more than one, so a Mac with
# several certificates never signs with the wrong one. MACPULSE_SIGNING_IDENTITY (a full
# name or SHA-1) overrides the search.
set -euo pipefail
: "${MACPULSE_TEAM_ID:?not set}"
MATCHES=$(security find-identity -v -p codesigning \
  | sed -nE 's/^ *[0-9]+\) ([0-9A-F]{40}) "(Developer ID Application: .*\('"$MACPULSE_TEAM_ID"'\))"$/\1\t\2/p' \
  | sort -u)
if [ -n "${MACPULSE_SIGNING_IDENTITY:-}" ]; then
  MATCHES=$(printf '%s\n' "$MATCHES" | awk -F'\t' -v id="$MACPULSE_SIGNING_IDENTITY" '$1 == id || $2 == id')
fi
COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
if [ "$COUNT" -ne 1 ]; then
  echo "Expected exactly one Developer ID Application identity for team $MACPULSE_TEAM_ID, found $COUNT." >&2
  echo "Set MACPULSE_SIGNING_IDENTITY to the full name or SHA-1 of the one to use." >&2
  exit 1
fi
printf '%s\n' "$MATCHES"
