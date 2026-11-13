#!/bin/bash
# Build FluxClone.app (no Xcode needed). Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

APP="build/FluxClone.app"
mkdir -p build
swiftc -O -target "$(uname -m)-apple-macos13.0" \
    -framework AppKit -framework CoreLocation -framework ServiceManagement \
    Sources/FluxClone/*.swift -o build/FluxClone
BIN="build/FluxClone"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FluxClone"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x FluxClone 2>/dev/null || true
    rm -rf "$HOME/Applications/FluxClone.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed to ~/Applications/FluxClone.app"
    open "$HOME/Applications/FluxClone.app"
fi
