#!/bin/bash
# Builds "AULA Studio.app" into ./build.
# Usage: scripts/build-app.sh [--universal]   (--universal builds for Apple silicon and Intel)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.3.0"

if [[ "${1:-}" == "--universal" ]]; then
    # Build each architecture separately and merge them (multi-arch builds need full Xcode).
    for ARCH in arm64 x86_64; do
        swift build -c release --triple "$ARCH-apple-macosx13.0"
    done
    BIN="build/AulaStudio-universal"
    mkdir -p build
    lipo -create \
        "$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/AulaStudio" \
        "$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/AulaStudio" \
        -output "$BIN"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/AulaStudio"
fi

APP="build/AULA Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AulaStudio"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AULA Studio</string>
    <key>CFBundleDisplayName</key><string>AULA Studio</string>
    <key>CFBundleIdentifier</key><string>local.aula-studio</string>
    <key>CFBundleExecutable</key><string>AulaStudio</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Music Rhythm can light your keyboard to sound from the microphone.</string>
    <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with AULA.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS can remember the app's permissions.
if [[ "${1:-}" == "--universal" ]]; then
    # Release builds: the default requirement pins this exact build.
    codesign --force --sign - --identifier local.aula-studio "$APP"
else
    # Development builds: require only the bundle identifier, so the Input
    # Monitoring permission survives rebuilds instead of being asked for again.
    codesign --force --sign - --identifier local.aula-studio \
        --requirements '=designated => identifier "local.aula-studio"' "$APP"
fi
echo "Built: $APP (v${VERSION})"
