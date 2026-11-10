#!/bin/bash
# Rebuilds Resources/AppIcon.icns from Resources/icon/AppIcon.svg using only macOS tools (AppKit SVG rendering, iconutil).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swift -module-cache-path "$TMP/module-cache" scripts/make-icon.swift Resources/icon/AppIcon.svg "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
echo "Built: Resources/AppIcon.icns"
