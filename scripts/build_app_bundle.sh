#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

pkill -x WeatherBarApp 2>/dev/null || true
swift build -c debug

APP="$ROOT/.build/WeatherBar.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/debug/WeatherBarApp" "$MACOS/WeatherBarApp"
cp "$ROOT/Resources/WeatherBar-Info.plist" "$CONTENTS/Info.plist"

SIGN_CANDIDATES=()
if [[ -n "${WEATHERBAR_CODESIGN_IDENTITY:-}" ]]; then
  SIGN_CANDIDATES+=("$WEATHERBAR_CODESIGN_IDENTITY")
fi

LOCAL_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/FriendOS Local Code Signing/ { print $2; exit }')"
if [[ -n "$LOCAL_IDENTITY" ]]; then
  SIGN_CANDIDATES+=("$LOCAL_IDENTITY")
fi

APPLE_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development:/ { print $2; exit }')"
if [[ -n "$APPLE_IDENTITY" ]]; then
  SIGN_CANDIDATES+=("$APPLE_IDENTITY")
fi
SIGN_CANDIDATES+=("-")

SIGN_ERROR="$(mktemp)"
SIGNED=0
for SIGN_IDENTITY in "${SIGN_CANDIDATES[@]}"; do
  if codesign --force --sign "$SIGN_IDENTITY" "$APP" > /dev/null 2> "$SIGN_ERROR"; then
    SIGNED=1
    break
  fi
done

if [[ "$SIGNED" -ne 1 ]]; then
  cat "$SIGN_ERROR" >&2
  rm -f "$SIGN_ERROR"
  exit 1
fi
rm -f "$SIGN_ERROR"
echo "$APP"
