#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TAG="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "${TAG:-}" ]]; then
  echo "Usage: Tools/generate_appcast.sh <tag> [archives_dir]" >&2
  exit 2
fi

ARCHIVES_DIR="${2:-dist/release}"
ZIP_PATH="$ARCHIVES_DIR/MacTempMenuBar.zip"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "[sparkle] Missing zip for appcast: $ZIP_PATH" >&2
  exit 1
fi

SPARKLE_ED_KEY="${SPARKLE_ED_KEY:-}"
if [[ -z "$SPARKLE_ED_KEY" ]]; then
  echo "[sparkle] Appcast generation skipped (SPARKLE_ED_KEY is not set)"
  exit 0
fi

SPARKLE_ROOT="$("$ROOT_DIR/Tools/fetch_sparkle.sh")"

REPO="${GITHUB_REPOSITORY:-kmg0308/MacTempMenuBar}"
DOWNLOAD_PREFIX="https://github.com/$REPO/releases/download/$TAG/"

FEED_DIR="$(mktemp -d "$ROOT_DIR/dist/.sparkle-feed.XXXXXX")"
cp "$ZIP_PATH" "$FEED_DIR/"

echo "[sparkle] Generating appcast.xml (tag: $TAG)"
echo "$SPARKLE_ED_KEY" | "$SPARKLE_ROOT/bin/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  "$FEED_DIR" >/dev/null

cp "$FEED_DIR/appcast.xml" "$ARCHIVES_DIR/appcast.xml"
echo "[sparkle] Wrote: $ARCHIVES_DIR/appcast.xml"
