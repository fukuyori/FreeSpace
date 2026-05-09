# FreeSpace

FreeSpace is a small SwiftUI menu bar app for macOS that shows available disk space.

## Screenshot

![FreeSpace menu bar screenshot](docs/screenshot-menu-bar.svg)

## Features

- Menu bar app that does not appear in the Dock
- Monitors available space on the root volume `/`
- Refreshes every 5 seconds
- Shows `available space (available percentage)` in the menu bar
- Displays GB as whole numbers
- Displays TB with up to 2 decimal places, truncated rather than rounded
- Tracks daily available space and shows today / 1-week / 1-month deltas in the popover
  (delta lines display `-` until history old enough to compare against exists)
- Supports launch at login

FreeSpace combines lightweight capacity APIs and displays the largest valid available-space value from `volumeAvailableCapacityKey`, `volumeAvailableCapacityForImportantUsageKey`, `volumeAvailableCapacityForOpportunisticUsageKey`, and a `statfs` fallback. This avoids heavy disk scans and external commands while moving closer to Finder or System Settings "Available" storage when macOS reports purgeable capacity through Foundation. If macOS does not report purgeable capacity through these APIs, FreeSpace falls back to the raw APFS/POSIX free-space value.

## Requirements

- macOS
- Xcode

## Build

```bash
xcodebuild -project FreeSpace.xcodeproj -scheme FreeSpace -configuration Debug -derivedDataPath DerivedData build
```

## Run

```bash
open DerivedData/Build/Products/Debug/FreeSpace.app
```

You can also launch the binary directly:

```bash
DerivedData/Build/Products/Debug/FreeSpace.app/Contents/MacOS/FreeSpace
```

## Packaging

Create a release build (signed with Developer ID Application + Hardened Runtime):

```bash
./scripts/build-release.sh
```

Create a DMG:

```bash
./scripts/create-dmg.sh
```

Create a signed and notarized PKG:

```bash
./scripts/create-pkg.sh
```

This runs the release build, signs it with `Developer ID Application: Noriaki Fukuyori (Q6GG27UYG5)`, packages it with `pkgbuild` signed by the matching `Developer ID Installer` certificate, then submits it to Apple's notary service and staples the ticket to the resulting `.pkg`.

Artifacts are written to `dist/`.

### Notarization setup

The notarization step uses `xcrun notarytool` with credentials stored in the keychain. Register them once:

```bash
xcrun notarytool store-credentials freespace-notary \
  --apple-id <your-apple-id> \
  --team-id Q6GG27UYG5 \
  --password <app-specific-password>
```

Generate an app-specific password at <https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords.

Override the keychain profile name with `NOTARY_PROFILE=<name>` if you stored it under a different label.

To skip notarization (e.g. for a quick local build), set `SKIP_NOTARIZATION=1`:

```bash
SKIP_NOTARIZATION=1 ./scripts/create-pkg.sh
```

You can also run notarization on its own against an existing `.pkg`:

```bash
./scripts/notarize-pkg.sh dist/FreeSpace-1.2.0.pkg
```

### App Sandbox

App Sandbox is disabled in the project so that the Xcode-built app and the installed PKG share the same `UserDefaults` location (`~/Library/Preferences/org.spumoni.freespace.FreeSpace.plist`). Without this, the sandboxed Xcode build and the unsandboxed installed app would record their daily history into separate containers and the week / month deltas would only see whichever side recorded them.

## Version

The current app version is `1.2.0`.
