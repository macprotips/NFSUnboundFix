#!/bin/bash
# Builds "NFS Unbound Fix.app" (and NFSUnboundFix.zip) into ./build.
#
#   scripts/build-app.sh              # native architecture
#   UNIVERSAL=1 scripts/build-app.sh  # Apple Silicon + Intel (needs full Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building release binary"
swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

APP="build/NFS Unbound Fix.app"
echo "==> Assembling $APP"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NFSUnboundFix" "$APP/Contents/MacOS/NFSUnboundFix"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"   # ad-hoc, fine for your own Mac
fi

ditto -c -k --keepParent "$APP" build/NFSUnboundFix.zip
echo "==> Done: $APP"
