#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${CODEXBAR_BUILD_APP:-$PWD/build/CodexBar.app}"
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources" "$APP/Contents/PlugIns/CodexWidget.appex/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
# Development builds may use a distinct build number to refresh WidgetKit's cache.
if [ -n "${CODEXBAR_BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CODEXBAR_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -F "$APP/Contents/Frameworks" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' Sources/QuotaClient.swift Sources/P1Support.swift Sources/Themes.swift Sources/WidgetTheme.swift Widget/SharedSnapshot.swift Sources/CodexBar.swift -o "$APP/Contents/MacOS/CodexBar"
WIDGET="$APP/Contents/PlugIns/CodexWidget.appex"
cp Widget/Info.plist "$WIDGET/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)" "$WIDGET/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" "$WIDGET/Contents/Info.plist"
swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/build/module-cache" -application-extension -parse-as-library -Xlinker -e -Xlinker _NSExtensionMain Widget/SharedSnapshot.swift Widget/CodexWidget.swift -o "$WIDGET/Contents/MacOS/CodexWidget"
codesign --force --sign - --entitlements Widget/Widget.entitlements "$WIDGET"
codesign --force --sign - --entitlements Widget/App.entitlements "$APP"
echo "Built: $APP"
