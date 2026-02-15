#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="MacTempMenuBar"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Generate app icon (.icns).
ICON_PNG="$BUILD_DIR/AppIcon.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_ICNS="$BUILD_DIR/AppIcon.icns"

swift "$ROOT_DIR/Tools/generate_icon.swift" "$ICON_PNG" >/dev/null

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

function _sips_resize() {
  local w="$1"
  local h="$2"
  local out="$3"
  sips -z "$h" "$w" "$ICON_PNG" --out "$out" >/dev/null
}

_sips_resize 16 16 "$ICONSET_DIR/icon_16x16.png"
_sips_resize 32 32 "$ICONSET_DIR/icon_16x16@2x.png"
_sips_resize 32 32 "$ICONSET_DIR/icon_32x32.png"
_sips_resize 64 64 "$ICONSET_DIR/icon_32x32@2x.png"
_sips_resize 128 128 "$ICONSET_DIR/icon_128x128.png"
_sips_resize 256 256 "$ICONSET_DIR/icon_128x128@2x.png"
_sips_resize 256 256 "$ICONSET_DIR/icon_256x256.png"
_sips_resize 512 512 "$ICONSET_DIR/icon_256x256@2x.png"
_sips_resize 512 512 "$ICONSET_DIR/icon_512x512.png"
cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"

# Compile the SMC bridge.
clang \
  -c \
  -O2 \
  -Wall -Wextra \
  "$ROOT_DIR/App/SMCBridge.c" \
  -o "$BUILD_DIR/SMCBridge.o"

# Compile and link the Swift menu bar app.
swiftc \
  -parse-as-library \
  -O \
  -import-objc-header "$ROOT_DIR/App/BridgingHeader.h" \
  "$ROOT_DIR/App/AppMain.swift" \
  "$BUILD_DIR/SMCBridge.o" \
  -framework AppKit \
  -framework Foundation \
  -framework IOKit \
  -framework CoreFoundation \
  -o "$BUILD_DIR/${APP_NAME}"

# Build the .app bundle.
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/${APP_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Sign the app bundle.
# - If SIGN_IDENTITY is set, use Developer ID + Hardened Runtime (required for notarization).
# - Otherwise, fall back to ad-hoc sign for local usage.
if command -v codesign >/dev/null 2>&1; then
  if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign \
      --force \
      --sign "$SIGN_IDENTITY" \
      --timestamp \
      --options runtime \
      "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
  else
    codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
  fi
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp -R "$APP_DIR" "$DIST_DIR/"

echo "Built: $DIST_DIR/${APP_NAME}.app"
