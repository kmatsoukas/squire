#!/bin/bash
# Builds Squire in release mode and wraps it in dist/Squire.app.
# Usage: scripts/bundle.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP="dist/Squire.app"

swift build -c release --product Squire
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Squire" "$APP/Contents/MacOS/Squire"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Squire</string>
    <key>CFBundleDisplayName</key>
    <string>Squire</string>
    <key>CFBundleIdentifier</key>
    <string>com.kmatsoukas.squire</string>
    <key>CFBundleExecutable</key>
    <string>Squire</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets the local build run.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
