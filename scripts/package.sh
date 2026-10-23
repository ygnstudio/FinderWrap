#!/bin/bash
# Local preview packaging only. No certificate, notary service or network access.
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$PWD/build/DerivedData/Build/Products/Release/FinderWrap.app"
[[ -d "$source_app" ]] || { echo 'Run scripts/build.sh Release first.' >&2; exit 2; }
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$source_app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
output="$PWD/build/packages"
mkdir -p "$output"
stage=$(mktemp -d "$output/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$source_app" "$stage/FinderWrap.app"
architectures=$(/usr/bin/lipo "$stage/FinderWrap.app/Contents/MacOS/FinderWrap" -archs)
for architecture in arm64 x86_64; do
    [[ " $architectures " == *" $architecture "* ]] || { echo "Missing $architecture" >&2; exit 2; }
done
# '-' is ad-hoc signing: no keychain certificate is accessed or created.
/usr/bin/codesign --force --sign - "$stage/FinderWrap.app"
/usr/bin/codesign --verify --strict "$stage/FinderWrap.app"
archive="$output/FinderWrap-$version-preview-universal-adhoc.zip"
/usr/bin/ditto -c -k --keepParent "$stage/FinderWrap.app" "$archive"
(cd "$output" && /usr/bin/shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf 'Local preview, NOT Developer ID signed or notarized: %s\n' "$archive"
