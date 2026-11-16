#!/bin/bash
# Builds NotifyBridge.app into ./build. Notification Center requires a real, signed
# app bundle, so the bare `swift run` binary cannot post notifications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/NotifyBridge.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotifyBridge"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NotifyBridge"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for local use, no developer account needed.
codesign --force --sign - "$APP"

echo "Built $APP"
