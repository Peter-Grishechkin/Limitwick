#!/bin/bash
# Renders README images into docs/images (or the directory given as the first argument).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -parse-as-library Sources/QuotaClient.swift Sources/P1Support.swift Sources/Themes.swift Sources/QuotaCard.swift Sources/InterfaceViews.swift scripts/ReadmeScreenshots.swift -o build/readme-screenshots
build/readme-screenshots "${1:-docs/images}"
if command -v oxipng >/dev/null; then oxipng -q -o 4 --strip safe "${1:-docs/images}"/*.png; fi
