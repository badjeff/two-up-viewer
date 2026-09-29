#!/bin/bash
#
# Copyright (c) 2026 badjeff
# SPDX-License-Identifier: MIT
#
# Builds two-up-viewer.app.
#
# `swift build` produces a Mach-O that already carries an embedded Info.plist,
# so it behaves like a bundled app; this script wraps it in a real `.app` with
# its icon, an on-disk Info.plist that LaunchServices can read for the folder
# document type, and an ad-hoc signature. The Dock icon and the drag-onto-it
# gesture both depend on that bundle existing.
#
# Usage:
#   ./build-app.sh                     release, universal, icon rendered
#   ./build-app.sh debug               debug, universal, icon rendered
#   ./build-app.sh --quick             debug, host arch only, icon reused
#   ./build-app.sh --quick release     release, host arch only, icon reused
#
# `--quick` is for testing a source change, not for shipping. It drops to debug
# so the optimiser is out of the way, builds only the host architecture so the
# other slice is not cross-compiled from scratch, and reuses the last rendered
# icon. Everything else — bundling, Info.plist, ad-hoc signature, verification —
# is identical, so the app launches and takes folder drops the same way.

set -euo pipefail

cd "$(dirname "$0")"

APP="build/two-up-viewer.app"
SOURCES="Sources/two-up-viewer"
CACHED_ICON="build/AppIcon.icns"

usage() {
  sed -n '6,24p' "$0" | sed 's/^# \{0,1\}//'
}

CONFIG="release"
CONFIG_SET=0
QUICK=0

while [ $# -gt 0 ]; do
  case "$1" in
    debug|release)
      CONFIG="$1"
      CONFIG_SET=1
      ;;
    --quick|-q)
      QUICK=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'"
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$QUICK" = 1 ] && [ "$CONFIG_SET" = 0 ]; then
  CONFIG="debug"
fi

if [ "$QUICK" = 1 ]; then
  ARCHES=( "$(uname -m)" )
else
  ARCHES=(x86_64 arm64)
fi

echo "==> Building ($CONFIG, ${ARCHES[*]})"
SLICES=()
for ARCH in "${ARCHES[@]}"; do
  SCRATCH=".build/$CONFIG/$ARCH"
  echo "    [$ARCH]"
    swift build -c "$CONFIG" --product two-up-viewer --arch "$ARCH" --scratch-path "$SCRATCH" -Xswiftc -warnings-as-errors 2>&1 | sed 's/^/    /'
  SLICE="$(swift build -c "$CONFIG" --show-bin-path --arch "$ARCH" --scratch-path "$SCRATCH")/two-up-viewer"
  [ -x "$SLICE" ] || { echo "error: no $ARCH binary at $SLICE"; exit 1; }
  SLICES+=("$SLICE")
done

EXECUTABLE="$APP/Contents/MacOS/two-up-viewer"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${#SLICES[@]}" -eq 1 ]; then
  cp "${SLICES[0]}" "$EXECUTABLE"
else
  lipo -create "${SLICES[@]}" -output "$EXECUTABLE"
fi
chmod 755 "$EXECUTABLE"
cp "$SOURCES/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The icon is a fixed cost that a source change cannot invalidate, so reuse the
# last render unless make-icon.swift is the thing that moved.
if [ "$QUICK" = 1 ] && [ -f "$CACHED_ICON" ] \
   && [ "$CACHED_ICON" -nt Tools/make-icon.swift ]; then
  echo "==> Reusing cached icon"
  cp "$CACHED_ICON" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "==> Rendering icon"
  swift Tools/make-icon.swift build >/dev/null
  iconutil -c icns build/two-up-viewer.iconset -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf build/two-up-viewer.iconset
  mkdir -p build
  cp "$APP/Contents/Resources/AppIcon.icns" "$CACHED_ICON"
fi

# Ad-hoc signature. Without it macOS refuses the folder document type, because
# LaunchServices will not trust an unsigned bundle's declared handlers.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" 2>&1 | sed 's/^/    /'

echo "==> Verifying"
echo "    archs: $(lipo -archs "$EXECUTABLE")"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo
if [ "$QUICK" = 1 ]; then
  echo "Built $APP  (v$VERSION, --quick: $CONFIG, host arch only — not for shipping)"
else
  echo "Built $APP  (v$VERSION)"
  echo "Install with:  cp -R \"$APP\" /Applications/"
fi
