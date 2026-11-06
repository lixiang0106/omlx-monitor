#!/usr/bin/env bash
# Builds a self-contained oMLX Status HUD.app in ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="oMLX Status HUD"
APP="dist/${APP_NAME}.app"
SDK_FLAGS=(-framework AppKit -framework Foundation)

for tool in swiftc iconutil codesign; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing $tool. Install the Xcode Command Line Tools: xcode-select --install" >&2
    exit 1
  }
done

echo "==> Compiling"
rm -rf build dist
mkdir -p "build" "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -swift-version 5 -O "${SDK_FLAGS[@]}" \
  Sources/OMLXMonitor.swift -o "$APP/Contents/MacOS/OMLXMonitor"

echo "==> Rendering icon"
swift Sources/DrawIcon.swift build/Icon.iconset
iconutil -c icns build/Icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Assembling bundle"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Self-test"
"$APP/Contents/MacOS/OMLXMonitor" --self-test

echo
echo "Built: $APP"
echo "Open it with:  open \"$APP\""
echo "The HUD stays on top until you click x or Quit in the menu."
