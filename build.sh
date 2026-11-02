#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/CodexBar.app"
SPARKLE_VERSION="2.10.1"
SPARKLE_DIR="$PWD/build/sparkle-$SPARKLE_VERSION"
ARCHIVE="$SPARKLE_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
mkdir -p "$SPARKLE_DIR" "$PWD/build/module-cache"
if [ ! -f "$ARCHIVE" ]; then
    curl --fail --location --output "$ARCHIVE.download" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    mv "$ARCHIVE.download" "$ARCHIVE"
fi
echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c -
if [ ! -d "$SPARKLE_DIR/Sparkle.framework" ]; then
    tar -xf "$ARCHIVE" -C "$SPARKLE_DIR"
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -F "$APP/Contents/Frameworks" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' Sources/QuotaClient.swift Sources/P1Support.swift Sources/Themes.swift Sources/CodexBar.swift -o "$APP/Contents/MacOS/CodexBar"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
