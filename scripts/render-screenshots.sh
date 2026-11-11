#!/bin/bash
# Renders README images into docs/images (or the directory given as the first argument).
# The animated Sessions window needs ffmpeg; PNGs are compressed with oxipng when it is installed.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-docs/images}"
frames=build/readme-frames
mkdir -p build/module-cache "$out"
swiftc -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/build/module-cache" -parse-as-library \
    Sources/QuotaClient.swift Sources/P1Support.swift Sources/Themes.swift Sources/QuotaCard.swift Sources/InterfaceViews.swift \
    Sources/Sessions.swift Sources/SessionGrid.swift scripts/ReadmeScreenshots.swift -o build/readme-screenshots
build/readme-screenshots "$out" "$frames"
# oxipng skips sessions.png: it would drop the animation.
if command -v oxipng >/dev/null; then find "$out" -maxdepth 1 -name '*.png' ! -name sessions.png -exec oxipng -q -o 4 --strip safe {} +; fi
# The animated window is an APNG: full alpha for its shadow and a sixth of the size of a GIF.
# 12.5 fps is SessionLook.fastTick (0.08 s); -plays 0 loops forever. Without ffmpeg the existing file stays.
if command -v ffmpeg >/dev/null; then
    ffmpeg -v error -y -framerate 12.5 -i "$frames/sessions-%02d.png" -plays 0 -pred mixed -f apng "$out/sessions.png"
    echo "Wrote sessions.png (animated)"
else
    echo "ffmpeg not found: the animated sessions.png was not written" >&2
fi
