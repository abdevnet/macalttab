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
# permissions stick. Only an Apple Development cert from the DEVELOPMENT_TEAM in
# project.yml is used, so a cert from another team on this Mac is never picked;
# otherwise fall back to ad-hoc. Override with CODESIGN_IDENTITY (any identity,
# e.g. a self-signed code-signing cert).
team_identity() {
    local team=$1 hash
    for hash in $(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development/ {print $2}'); do
        if security find-certificate -a -Z -p | awk -v h="$hash" '
                /^SHA-1 hash:/ { found = ($3 == h) }
                found && /BEGIN CERTIFICATE/ { p = 1 }
                p { print }
                p && /END CERTIFICATE/ { exit }' |
            openssl x509 -noout -subject | grep -qE "OU ?= ?$team([,/]|$)"; then
            echo "$hash"
            return
        fi
    done
}

TEAM=$(awk '/DEVELOPMENT_TEAM:/ {print $2}' project.yml)
IDENTITY="${CODESIGN_IDENTITY:-$(team_identity "$TEAM")}"
if [[ -z "$IDENTITY" ]]; then
    echo "No Apple Development cert for team $TEAM; signing ad-hoc"
fi
codesign --force --sign "${IDENTITY:--}" "$BUNDLE"

echo "Built $BUNDLE"
