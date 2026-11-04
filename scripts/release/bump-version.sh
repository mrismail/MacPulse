#!/bin/bash
# Sets the marketing version (for example 1.0.1) in project.yml.
# The build number is not stored: release builds use the git commit count.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 MAJOR.MINOR.PATCH" >&2
  exit 1
fi
sed -i.bak -E "s/^( +MARKETING_VERSION: )\"[0-9.]+\"/\1\"$VERSION\"/" project.yml
rm -f project.yml.bak
grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml || { echo "project.yml was not updated" >&2; exit 1; }
echo "Version set to $VERSION. Commit project.yml and tag the release as v$VERSION."
