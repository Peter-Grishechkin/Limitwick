#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/CodexBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" Sources/QuotaClient.swift Sources/CodexBar.swift -o "$APP/Contents/MacOS/CodexBar"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
