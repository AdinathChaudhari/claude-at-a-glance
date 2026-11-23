#!/usr/bin/env bash
# Build the app and zip it for a GitHub release.
# Usage: VERSION=0.2.0 scripts/package-release.sh   (output: build/Claude-at-a-Glance-<version>.zip)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
export VERSION

bash scripts/build-app.sh

ZIP="build/Claude-at-a-Glance-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Claude at a Glance.app" "$ZIP"

echo "Packaged $ZIP"
shasum -a 256 "$ZIP"
