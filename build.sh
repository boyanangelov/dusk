#!/bin/zsh
# Builds build/Dusk.app (no Xcode needed; Command Line Tools are enough).
set -e
cd "$(dirname "$0")"
APP=build/Dusk.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos11 \
    -framework AppKit -framework CoreLocation \
    Sources/Dusk/*.swift -o "$APP/Contents/MacOS/Dusk"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Built $APP — run with: open $APP"
