#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/WeatherBar-Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/WeatherBar-Info.plist)}"
TAG="${TAG:-v$VERSION}"
PKG_IDENTIFIER="${PKG_IDENTIFIER:-local.weatherbar.pkg}"
PUBLISH=0

usage() {
  cat <<EOF
Usage: VERSION=0.1.0 TAG=v0.1.0 scripts/release.sh [--publish]

Builds dist/release/\$TAG/WeatherBar-\$VERSION.pkg.

Environment:
  WEATHERBAR_APP_SIGN_IDENTITY        App signing identity. Defaults to Developer ID, Apple Development, local, then ad hoc.
  WEATHERBAR_INSTALLER_SIGN_IDENTITY  Optional Developer ID Installer identity for the package.
  VERSION                             Release version. Defaults to Resources/WeatherBar-Info.plist.
  BUILD_NUMBER                        Bundle build number. Defaults to Resources/WeatherBar-Info.plist.
  TAG                                 GitHub release tag. Defaults to v\$VERSION.
  PKG_IDENTIFIER                      Package identifier. Defaults to local.weatherbar.pkg.
  ALLOW_DIRTY                         Set to 1 only for local script validation before committing.

Publishing:
  --publish requires GitHub CLI (gh) authenticated for origin.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish)
      PUBLISH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

require_clean_tree() {
  if [[ "${ALLOW_DIRTY:-0}" == "1" ]]; then
    return
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit or stash changes before releasing." >&2
    exit 1
  fi
}

first_identity() {
  local pattern="$1"
  security find-identity -v -p codesigning | awk -F '"' -v pattern="$pattern" '$0 ~ pattern { print $2; exit }'
}

app_sign_candidates() {
  if [[ -n "${WEATHERBAR_APP_SIGN_IDENTITY:-}" ]]; then
    echo "$WEATHERBAR_APP_SIGN_IDENTITY"
  fi

  local identity
  identity="$(first_identity 'Developer ID Application:')"
  if [[ -n "$identity" ]]; then
    echo "$identity"
  fi

  identity="$(first_identity 'FriendOS Local Code Signing')"
  if [[ -n "$identity" ]]; then
    echo "$identity"
  fi

  identity="$(first_identity 'Apple Development:')"
  if [[ -n "$identity" ]]; then
    echo "$identity"
  fi

  echo "-"
}

require_clean_tree

RELEASE_DIR="$ROOT/dist/release/$TAG"
PAYLOAD_DIR="$RELEASE_DIR/payload"
APP_NAME="WeatherBar.app"
PKG_UNSIGNED="$RELEASE_DIR/WeatherBar-$VERSION-unsigned.pkg"
PKG_PATH="$RELEASE_DIR/WeatherBar-$VERSION.pkg"

rm -rf "$RELEASE_DIR"
mkdir -p "$PAYLOAD_DIR"

BUILT_APP="$(scripts/build_app_bundle.sh | tail -n 1)"
COPYFILE_DISABLE=1 ditto --norsrc "$BUILT_APP" "$PAYLOAD_DIR/$APP_NAME"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PAYLOAD_DIR/$APP_NAME/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PAYLOAD_DIR/$APP_NAME/Contents/Info.plist"

APP_SIGN_ERROR="$(mktemp)"
APP_SIGNED=0
APP_SIGN_IDENTITY=""
while IFS= read -r candidate; do
  [[ -z "$candidate" ]] && continue
  if codesign --force --deep --options runtime --sign "$candidate" "$PAYLOAD_DIR/$APP_NAME" > /dev/null 2> "$APP_SIGN_ERROR"; then
    APP_SIGNED=1
    APP_SIGN_IDENTITY="$candidate"
    break
  fi
done < <(app_sign_candidates)

if [[ "$APP_SIGNED" -ne 1 ]]; then
  cat "$APP_SIGN_ERROR" >&2
  rm -f "$APP_SIGN_ERROR"
  exit 1
fi
rm -f "$APP_SIGN_ERROR"

echo "Signed app with: $APP_SIGN_IDENTITY"
xattr -cr "$PAYLOAD_DIR/$APP_NAME" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$PAYLOAD_DIR/$APP_NAME"

COPYFILE_DISABLE=1 pkgbuild \
  --component "$PAYLOAD_DIR/$APP_NAME" \
  --install-location /Applications \
  --identifier "$PKG_IDENTIFIER" \
  --version "$VERSION" \
  "$PKG_UNSIGNED"

PKG_SIGN_IDENTITY="${WEATHERBAR_INSTALLER_SIGN_IDENTITY:-$(first_identity 'Developer ID Installer:')}"
if [[ -n "$PKG_SIGN_IDENTITY" ]]; then
  productsign --sign "$PKG_SIGN_IDENTITY" "$PKG_UNSIGNED" "$PKG_PATH"
  rm -f "$PKG_UNSIGNED"
else
  mv "$PKG_UNSIGNED" "$PKG_PATH"
fi

pkgutil --check-signature "$PKG_PATH" || true
echo "$PKG_PATH"

if [[ "$PUBLISH" -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) is required for --publish." >&2
    exit 1
  fi

  gh auth status >/dev/null
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$PKG_PATH" --clobber
  else
    gh release create "$TAG" "$PKG_PATH" \
      --target "$(git rev-parse HEAD)" \
      --title "WeatherBar $VERSION" \
      --notes "WeatherBar $VERSION package installer."
  fi
fi
