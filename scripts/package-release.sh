#!/bin/bash
# Builds a universal (Apple silicon + Intel) app and zips it for a GitHub release.
# Usage: scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release SelfCheck
scripts/build-app.sh --universal
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/AULA Studio.app/Contents/Info.plist")
mkdir -p dist
ZIP="dist/AULA-Studio-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "build/AULA Studio.app" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Release archive: $ZIP"
