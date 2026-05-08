#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-release.sh"
DIST_DIR="$ROOT_DIR/dist"
SCRIPTS_DIR="$DIST_DIR/pkg-scripts"
APP_PATH="$("$BUILD_SCRIPT")"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

normalize_pkg_version() {
  local raw_version="$1"
  local -a parts
  parts=("${(@s:.:)raw_version}")

  if (( ${#parts[@]} == 2 )); then
    echo "${parts[1]}.${parts[2]}.0"
    return
  fi

  if (( ${#parts[@]} == 3 )); then
    echo "$raw_version"
    return
  fi

  echo "Expected version with 2 or 3 numeric components, got: $raw_version" >&2
  exit 1
}

APP_NAME="$(basename "$APP_PATH")"
APP_BASENAME="${APP_NAME:r}"
IDENTIFIER="$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
RAW_VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
VERSION="$(normalize_pkg_version "$RAW_VERSION")"
PKG_PATH="$DIST_DIR/${APP_BASENAME}-${VERSION}.pkg"

mkdir -p "$DIST_DIR"
rm -rf "$SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"
cat > "$SCRIPTS_DIR/preinstall" <<'SCRIPT'
#!/bin/zsh

/usr/bin/pkill -x FreeSpace 2>/dev/null || true
exit 0
SCRIPT
chmod +x "$SCRIPTS_DIR/preinstall"
rm -f "$PKG_PATH"

INSTALLER_SIGN_IDENTITY="Developer ID Installer: Noriaki Fukuyori (Q6GG27UYG5)"

COPYFILE_DISABLE=1 pkgbuild \
  --component "$APP_PATH" \
  --install-location /Applications \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --scripts "$SCRIPTS_DIR" \
  --sign "$INSTALLER_SIGN_IDENTITY" \
  "$PKG_PATH"

if [[ "${SKIP_NOTARIZATION:-0}" == "1" ]]; then
  echo "SKIP_NOTARIZATION=1 set, skipping notarization." >&2
else
  "$ROOT_DIR/scripts/notarize-pkg.sh" "$PKG_PATH" >&2
fi

echo "$PKG_PATH"
