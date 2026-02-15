#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"

VENDOR_ROOT="$ROOT_DIR/.vendor/sparkle/$SPARKLE_VERSION"
ARCHIVE_PATH="$VENDOR_ROOT/Sparkle-$SPARKLE_VERSION.tar.xz"
FRAMEWORK_DIR="$VENDOR_ROOT/Sparkle.framework"

mkdir -p "$VENDOR_ROOT"

if [[ ! -d "$FRAMEWORK_DIR" ]]; then
  url="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "[sparkle] Downloading Sparkle $SPARKLE_VERSION..."
  curl -fL -o "$ARCHIVE_PATH" "$url"

  echo "[sparkle] Extracting..."
  tar -xJf "$ARCHIVE_PATH" -C "$VENDOR_ROOT"
fi

if [[ ! -d "$FRAMEWORK_DIR" ]]; then
  echo "[sparkle] Sparkle.framework not found after extraction: $FRAMEWORK_DIR" >&2
  exit 1
fi

echo "$VENDOR_ROOT"

