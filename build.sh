#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
CONFIGURATION="${CODEXBAR_BUILD_CONFIGURATION:-development}"
case "$CONFIGURATION" in
    development) DEFAULT_APP="$PWD/build/CodexBar-Development.app"; SWIFT_FLAGS=(-D CODEXBAR_DEVELOPMENT) ;;
    release) DEFAULT_APP="$PWD/build/CodexBar.app"; SWIFT_FLAGS=() ;;
    *) echo "Unknown CODEXBAR_BUILD_CONFIGURATION: $CONFIGURATION" >&2; exit 1 ;;
esac
APP="${CODEXBAR_BUILD_APP:-$DEFAULT_APP}"
SPARKLE_VERSION="2.10.1"
SPARKLE_DIR="$PWD/build/sparkle-$SPARKLE_VERSION"
ARCHIVE="$SPARKLE_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
LOTTIE_VERSION="4.5.2"
LOTTIE_DIR="$PWD/build/lottie-$LOTTIE_VERSION"
LOTTIE_ARCHIVE="$LOTTIE_DIR/Lottie.xcframework.zip"
LOTTIE_SHA256="92206ff6af80373903767214ac16215838f6da11dedca789c0439299b46b6694"
mkdir -p "$SPARKLE_DIR" "$PWD/build/module-cache"
mkdir -p "$LOTTIE_DIR"
if [ ! -f "$LOTTIE_ARCHIVE" ]; then
    curl --fail --location --output "$LOTTIE_ARCHIVE.download" "https://github.com/airbnb/lottie-ios/releases/download/$LOTTIE_VERSION/Lottie.xcframework.zip"
    mv "$LOTTIE_ARCHIVE.download" "$LOTTIE_ARCHIVE"
fi
echo "$LOTTIE_SHA256  $LOTTIE_ARCHIVE" | shasum -a 256 -c -
if [ ! -d "$LOTTIE_DIR/Lottie.xcframework/macos-arm64_x86_64/Lottie.framework" ]; then
    unzip -oq "$LOTTIE_ARCHIVE" 'Lottie.xcframework/macos-arm64_x86_64/*' -d "$LOTTIE_DIR"
fi
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
APP_ENTITLEMENTS="$PWD/build/app-$CONFIGURATION.entitlements"
WIDGET_ENTITLEMENTS="$PWD/build/widget-$CONFIGURATION.entitlements"
cp Widget/App.entitlements "$APP_ENTITLEMENTS"
cp Widget/Widget.entitlements "$WIDGET_ENTITLEMENTS"
if [ "$CONFIGURATION" = development ]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.codexbar.development' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName Codex Bar Development' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :com.apple.security.application-groups:0 group.local.codexbar.development.shared' "$APP_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c 'Set :com.apple.security.application-groups:0 group.local.codexbar.development.shared' "$WIDGET_ENTITLEMENTS"
fi
# Development builds may use a distinct build number to refresh WidgetKit's cache.
if [ -n "${CODEXBAR_BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CODEXBAR_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$LOTTIE_DIR/Lottie.xcframework/macos-arm64_x86_64/Lottie.framework" "$APP/Contents/Frameworks/Lottie.framework"
ditto Resources/useAnimations "$APP/Contents/Resources/useAnimations"
swiftc ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -F "$APP/Contents/Frameworks" -framework Sparkle -framework Lottie -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' Sources/QuotaClient.swift Sources/P1Support.swift Sources/AppSettings.swift Sources/NoticeService.swift Sources/RefreshCoordinator.swift Sources/Activity.swift Sources/Themes.swift Sources/WidgetTheme.swift Widget/SharedSnapshot.swift Sources/InterfaceViews.swift Sources/PanelInterface.swift Sources/ThemeInterface.swift Sources/SettingsInterface.swift Sources/MenuInterface.swift Sources/CodexBar.swift -o "$APP/Contents/MacOS/CodexBar"
WIDGET="$APP/Contents/PlugIns/CodexWidget.appex"
cp Widget/Info.plist "$WIDGET/Contents/Info.plist"
if [ "$CONFIGURATION" = development ]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.codexbar.development.widget' "$WIDGET/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Codex Bar Development' "$WIDGET/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)" "$WIDGET/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" "$WIDGET/Contents/Info.plist"
swiftc ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$PWD/build/module-cache" -application-extension -parse-as-library -Xlinker -e -Xlinker _NSExtensionMain Widget/SharedSnapshot.swift Widget/CodexWidget.swift -o "$WIDGET/Contents/MacOS/CodexWidget"
codesign --force --sign - --entitlements "$WIDGET_ENTITLEMENTS" "$WIDGET"
codesign --force --sign - "$APP/Contents/Frameworks/Lottie.framework"
codesign --force --sign - --entitlements "$APP_ENTITLEMENTS" "$APP"
echo "Built: $APP"
