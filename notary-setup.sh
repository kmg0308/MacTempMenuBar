#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="${NOTARY_PROFILE:-mactemp-notary}"

function usage() {
  cat <<'EOF'
Usage:
  # Option A) Apple ID + app-specific password
  APPLE_ID="you@example.com" \
  APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
  TEAM_ID="ABCDE12345" \
  NOTARY_PROFILE="mactemp-notary" \
  ./notary-setup.sh

  # Option B) App Store Connect API key
  ASC_KEY_PATH="/absolute/path/AuthKey_XXXXXX.p8" \
  ASC_KEY_ID="XXXXXX1234" \
  ASC_ISSUER="00000000-0000-0000-0000-000000000000" \
  NOTARY_PROFILE="mactemp-notary" \
  ./notary-setup.sh

Then package with notarization:
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_KEYCHAIN_PROFILE="mactemp-notary" \
  bash package.sh
EOF
}

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode Command Line Tools first." >&2
  exit 1
fi

if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" ]]; then
  args=(
    store-credentials
    "$PROFILE_NAME"
    --key "$ASC_KEY_PATH"
    --key-id "$ASC_KEY_ID"
    --validate
  )
  if [[ -n "${ASC_ISSUER:-}" ]]; then
    args+=(--issuer "$ASC_ISSUER")
  fi
  xcrun notarytool "${args[@]}"
  echo "Saved notary profile: $PROFILE_NAME (API key mode)"
  exit 0
fi

if [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" && -n "${TEAM_ID:-}" ]]; then
  xcrun notarytool store-credentials \
    "$PROFILE_NAME" \
    --apple-id "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID" \
    --validate
  echo "Saved notary profile: $PROFILE_NAME (Apple ID mode)"
  exit 0
fi

usage
exit 1
