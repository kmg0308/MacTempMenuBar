#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MacTempMenuBar"
APP_BUNDLE="${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_BUNDLE"
RELEASE_DIR="$DIST_DIR/release"
DMG_STAGING_DIR="$DIST_DIR/.dmg-staging"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-20m}"
NOTARIZE_DMG="${NOTARIZE_DMG:-1}"

cd "$ROOT_DIR"

function require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

function notarize_wait() {
  local archive_path="$1"
  xcrun notarytool submit \
    "$archive_path" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait \
    --timeout "$NOTARY_TIMEOUT"
}

# 1) Build latest app bundle (signed if SIGN_IDENTITY is provided).
SIGN_IDENTITY="$SIGN_IDENTITY" "$ROOT_DIR/build.sh" >/dev/null

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

BIN_PATH="$APP_PATH/Contents/MacOS/$APP_NAME"
ARCH_SUFFIX="unknown"
if command -v lipo >/dev/null 2>&1; then
  ARCHS="$(lipo -archs "$BIN_PATH" 2>/dev/null || true)"
  if [[ "$ARCHS" == *"arm64"* && "$ARCHS" == *"x86_64"* ]]; then
    ARCH_SUFFIX="universal"
  elif [[ "$ARCHS" == *"arm64"* ]]; then
    ARCH_SUFFIX="arm64"
  elif [[ "$ARCHS" == *"x86_64"* ]]; then
    ARCH_SUFFIX="x86_64"
  fi
fi
if [[ "$ARCH_SUFFIX" == "unknown" ]]; then
  ARCH_SUFFIX="$(uname -m)"
fi

BASE_NAME="${APP_NAME}-v${VERSION}-${TIMESTAMP}-macOS-${ARCH_SUFFIX}"
ZIP_PATH="$RELEASE_DIR/${BASE_NAME}.zip"
DMG_PATH="$RELEASE_DIR/${BASE_NAME}.dmg"
NOTARY_APP_ZIP="$DIST_DIR/.notary-${BASE_NAME}.zip"

mkdir -p "$RELEASE_DIR"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"

if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
  require_command xcrun
  require_command ditto

  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "NOTARY_KEYCHAIN_PROFILE is set, but SIGN_IDENTITY is empty." >&2
    echo "Set SIGN_IDENTITY='Developer ID Application: ... (TEAMID)' and retry." >&2
    exit 1
  fi

  # Preflight check that the keychain profile is usable.
  xcrun notarytool history \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --output-format json >/dev/null

  # Notarize the .app first, then staple it. ZIP/DMG created later inherit this.
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_APP_ZIP"
  echo "[notary] Submitting app archive..."
  notarize_wait "$NOTARY_APP_ZIP"
  rm -f "$NOTARY_APP_ZIP"

  echo "[notary] Stapling app..."
  xcrun stapler staple -v "$APP_PATH"
  xcrun stapler validate -v "$APP_PATH"
fi

# 2) ZIP package (best for chat apps / quick sharing).
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

# 3) DMG package (drag-and-drop install style).
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING_DIR"

if [[ -n "$NOTARY_KEYCHAIN_PROFILE" && "$NOTARIZE_DMG" == "1" ]]; then
  echo "[notary] Submitting dmg..."
  notarize_wait "$DMG_PATH"

  echo "[notary] Stapling dmg..."
  xcrun stapler staple -v "$DMG_PATH"
  xcrun stapler validate -v "$DMG_PATH"
fi

echo "Created:"
echo " - $ZIP_PATH"
echo " - $DMG_PATH"
if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
  echo "Notarization: enabled (profile: $NOTARY_KEYCHAIN_PROFILE)"
else
  echo "Notarization: disabled (set NOTARY_KEYCHAIN_PROFILE to enable)"
fi
