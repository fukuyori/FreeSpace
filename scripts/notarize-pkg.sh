#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-freespace-notary}"

if (( $# >= 1 )); then
  PKG_PATH="$1"
else
  PKG_PATH="$(ls -1t "$DIST_DIR"/*.pkg 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "${PKG_PATH:-}" || ! -f "$PKG_PATH" ]]; then
  echo "Usage: $0 [path/to/file.pkg]" >&2
  echo "No .pkg found in $DIST_DIR" >&2
  exit 1
fi

if ! /usr/bin/security find-generic-password -s "com.apple.gke.notary.tool" -a "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
Notary keychain profile "$KEYCHAIN_PROFILE" not found.

Create it once with:

  xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \\
    --apple-id <your-apple-id> \\
    --team-id Q6GG27UYG5 \\
    --password <app-specific-password>

Get an app-specific password at https://appleid.apple.com -> Sign-In and Security -> App-Specific Passwords.
Override the profile name with NOTARY_PROFILE=<name> $0
EOF
  exit 1
fi

echo "Submitting $PKG_PATH to Apple notary service (profile: $KEYCHAIN_PROFILE)..." >&2

xcrun notarytool submit "$PKG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "Stapling notarization ticket..." >&2
xcrun stapler staple "$PKG_PATH"

echo "Validating staple..." >&2
xcrun stapler validate "$PKG_PATH"

echo "Verifying with spctl..." >&2
/usr/sbin/spctl --assess --type install --verbose=2 "$PKG_PATH" || true

echo "$PKG_PATH"
