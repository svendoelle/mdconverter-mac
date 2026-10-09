#!/bin/bash
# Builds a universal "MD Converter.app" into ./build (requires Xcode command line tools).
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary needs full Xcode; fall back to the native architecture otherwise.
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCHS[@]}" 2>/dev/null; then
    echo "Universal build unavailable (Xcode not installed?) - building for this Mac only."
    ARCHS=()
    swift build -c release
fi
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/MD Converter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MDConverter" "$APP/Contents/MacOS/MDConverter"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built: $APP"
