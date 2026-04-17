#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-release.sh"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$("$BUILD_SCRIPT")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

APP_NAME="$(basename "$APP_PATH")"
APP_BASENAME="${APP_NAME:r}"
IDENTIFIER="$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
PKG_PATH="$DIST_DIR/${APP_BASENAME}-${VERSION}.pkg"

mkdir -p "$DIST_DIR"
rm -f "$PKG_PATH"

pkgbuild \
  --component "$APP_PATH" \
  --install-location /Applications \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$PKG_PATH"

echo "$PKG_PATH"
