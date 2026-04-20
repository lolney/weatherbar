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

codesign --force --sign - "$APP" >/dev/null
echo "$APP"
