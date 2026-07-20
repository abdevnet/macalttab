#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP=MyAltTab
BUNDLE="build/$APP.app"
mkdir -p "$BUNDLE/Contents/MacOS"

ARCH=$(uname -m)
# dynamic_lookup: the SkyLight symbols aren't in any SDK tbd; they resolve at
# runtime since SkyLight is loaded into every GUI process.
xcrun swiftc -O \
    -target "$ARCH-apple-macos14.0" \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    Sources/*.swift \
    -o "$BUNDLE/Contents/MacOS/$APP"

cp Info.plist "$BUNDLE/Contents/Info.plist"

# A real signing identity keeps the signature stable across rebuilds so TCC
# permissions stick; fall back to ad-hoc if none is available.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$BUNDLE"

echo "Built $BUNDLE"
