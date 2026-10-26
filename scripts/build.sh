#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
case "$configuration" in Debug) optimization=-Onone ;; Release) optimization=-O ;; *) echo 'Usage: scripts/build.sh [Debug|Release]' >&2; exit 2 ;; esac
[[ $# -le 1 ]] || exit 2
output="$PWD/build/Products/$configuration"
mkdir -p "$output"
stage=$(mktemp -d "$output/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/FinderWrap.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$stage/AppIcon.iconset"
cp Rebuild/Host/Info.plist "$app/Contents/Info.plist"
xcrun swiftc -parse-as-library -swift-version 5 "$optimization" -target arm64-apple-macos13.0 \
    -module-cache-path "$PWD/build/ModuleCache" \
    Rebuild/Sources/FinderBridge/*.swift Rebuild/Host/CandidateApp.swift \
    -o "$app/Contents/MacOS/FinderWrap"
for icon in Resources/Assets.xcassets/AppIcon.appiconset/*.png; do
    filename=$(basename "$icon")
    cp "$icon" "$stage/AppIcon.iconset/${filename/@1x/}"
done
iconutil -c icns "$stage/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
python3 scripts/check-minimum-system.py "$app"
# Only replace generated build output after successful compilation.
rm -rf "$output/FinderWrap.app"
mv "$app" "$output/FinderWrap.app"
printf 'FinderWrap %s built: %s (not an installation package)\n' "$configuration" "$output/FinderWrap.app"
