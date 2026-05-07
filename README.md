# FreeSpace

FreeSpace is a small SwiftUI menu bar app for macOS that shows available disk space.

## Screenshot

![FreeSpace menu bar screenshot](docs/screenshot-menu-bar.svg)

## Features

- Menu bar app that does not appear in the Dock
- Monitors free space on the root volume `/`
- Refreshes every 5 seconds
- Shows `free space (free percentage)` in the menu bar
- Displays GB as whole numbers
- Displays TB with up to 2 decimal places, truncated rather than rounded
- Supports launch at login

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

Create a release build:

```bash
./scripts/build-release.sh
```

Create a DMG:

```bash
./scripts/create-dmg.sh
```

Create a PKG:

```bash
./scripts/create-pkg.sh
```

Artifacts are written to `dist/`.

These scripts build the app without code signing so you can generate local `.dmg` and `.pkg` artifacts in a development environment.

## Version

The current app version is `1.1.1`.
