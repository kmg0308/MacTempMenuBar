#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="MacTempMenuBar"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

function require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

require_command xcrun
require_command lipo

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

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

# Compile a universal binary (arm64 + x86_64) so releases work on both Apple Silicon and Intel Macs.
TARGET_TRIPLE_ARM64="arm64-apple-macos13.0"
TARGET_TRIPLE_X86_64="x86_64-apple-macos13.0"

SMC_OBJ_ARM64="$BUILD_DIR/SMCBridge-arm64.o"
SMC_OBJ_X86_64="$BUILD_DIR/SMCBridge-x86_64.o"

BIN_ARM64="$BUILD_DIR/${APP_NAME}-arm64"
BIN_X86_64="$BUILD_DIR/${APP_NAME}-x86_64"

# Compile the SMC bridge (per-arch).
clang -c -O2 -Wall -Wextra -isysroot "$SDKROOT" -target "$TARGET_TRIPLE_ARM64" "$ROOT_DIR/App/SMCBridge.c" -o "$SMC_OBJ_ARM64"
clang -c -O2 -Wall -Wextra -isysroot "$SDKROOT" -target "$TARGET_TRIPLE_X86_64" "$ROOT_DIR/App/SMCBridge.c" -o "$SMC_OBJ_X86_64"

# Compile and link the Swift menu bar app (per-arch).
swiftc \
  -parse-as-library \
  -O \
  -sdk "$SDKROOT" \
  -target "$TARGET_TRIPLE_ARM64" \
  -import-objc-header "$ROOT_DIR/App/BridgingHeader.h" \
  "$ROOT_DIR/App/AppMain.swift" \
  "$SMC_OBJ_ARM64" \
  -framework AppKit \
  -framework Foundation \
  -framework IOKit \
  -framework CoreFoundation \
  -o "$BIN_ARM64"

swiftc \
  -parse-as-library \
  -O \
  -sdk "$SDKROOT" \
  -target "$TARGET_TRIPLE_X86_64" \
  -import-objc-header "$ROOT_DIR/App/BridgingHeader.h" \
  "$ROOT_DIR/App/AppMain.swift" \
  "$SMC_OBJ_X86_64" \
  -framework AppKit \
  -framework Foundation \
  -framework IOKit \
  -framework CoreFoundation \
  -o "$BIN_X86_64"

# Combine into a universal binary.
lipo -create -output "$BUILD_DIR/${APP_NAME}" "$BIN_ARM64" "$BIN_X86_64"

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
