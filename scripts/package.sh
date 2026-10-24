#!/bin/bash
# Fixed-identity distribution by default. Ad-hoc is explicit and local-only.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:---fixed}"
case "$mode" in
    --fixed)
        identity=$(python3 scripts/signing-policy.py identity)
        requirement=$(python3 scripts/signing-policy.py requirement)
        lane=fixed
        ;;
    --ad-hoc)
        [[ "${CI:-false}" != true && "${GITHUB_ACTIONS:-false}" != true ]] || {
            echo 'Ad-hoc installation packages are forbidden in CI.' >&2; exit 2;
        }
        identity=-
        lane=adhoc
        ;;
    *) echo 'Usage: scripts/package.sh [--fixed|--ad-hoc]' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2
source_app="$PWD/build/DerivedData/Build/Products/Release/FinderWrap.app"
[[ -d "$source_app" ]] || { echo 'Run scripts/build.sh Release first.' >&2; exit 2; }
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$source_app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$source_app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[[ "$build" =~ ^[0-9]+$ ]] || exit 2
output="$PWD/build/packages"
mkdir -p "$output"
name="FinderWrap-$version-b$build-$lane-universal"
for extension in dmg zip sha256 signing.json; do
    [[ ! -e "$output/$name.$extension" ]] || { echo "Package already exists: $name.$extension (preserve or move it before rebuilding)." >&2; exit 2; }
done
stage=$(mktemp -d "$output/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/payload"
/usr/bin/ditto --norsrc --noextattr "$source_app" "$stage/payload/FinderWrap.app"
architectures=$(/usr/bin/lipo "$stage/payload/FinderWrap.app/Contents/MacOS/FinderWrap" -archs)
for architecture in arm64 x86_64; do
    [[ " $architectures " == *" $architecture "* ]] || { echo "Missing $architecture" >&2; exit 2; }
done
# Ordinary Xcode build products keep debug-map paths even in Release. Strip
# debug symbols before signing so distribution does not reveal the build host.
/usr/bin/xcrun strip -S "$stage/payload/FinderWrap.app/Contents/MacOS/FinderWrap"
sign_args=(--force --sign "$identity" --options runtime --timestamp=none)
if [[ "$mode" == --fixed ]]; then
    sign_args+=(--requirements "=$requirement")
    if [[ -n "${FINDERWRAP_SIGNING_KEYCHAIN:-}" ]]; then
        sign_args+=(--keychain "$FINDERWRAP_SIGNING_KEYCHAIN")
    fi
fi
/usr/bin/codesign "${sign_args[@]}" "$stage/payload/FinderWrap.app"
/usr/bin/codesign --verify --strict "$stage/payload/FinderWrap.app"
if [[ "$mode" == --fixed ]]; then
    python3 scripts/signing-policy.py verify "$stage/payload/FinderWrap.app" > "$stage/$name.signing.json"
    cp "$stage/$name.signing.json" "$stage/payload/Signing.json"
fi
cp docs/installation.html "$stage/payload/Install.html"
cp LICENSE "$stage/payload/LICENSE.txt"
ln -s /Applications "$stage/payload/Applications"
/usr/bin/hdiutil create -quiet -volname "FinderWrap $version" -srcfolder "$stage/payload" \
    -format UDZO -fs HFS+ "$stage/$name.dmg"
# A ZIP alternative carries the same signed app and instructions, without a symlink.
mkdir "$stage/zip"
/usr/bin/ditto --norsrc --noextattr "$stage/payload/FinderWrap.app" "$stage/zip/FinderWrap.app"
cp "$stage/payload/Install.html" "$stage/zip/Install.html"
cp "$stage/payload/LICENSE.txt" "$stage/zip/LICENSE.txt"
if [[ "$mode" == --fixed ]]; then cp "$stage/payload/Signing.json" "$stage/zip/Signing.json"; fi
/usr/bin/ditto --norsrc --noextattr -c -k "$stage/zip" "$stage/$name.zip"
for extension in dmg zip; do mv "$stage/$name.$extension" "$output/$name.$extension"; done
if [[ "$mode" == --fixed ]]; then mv "$stage/$name.signing.json" "$output/$name.signing.json"; fi
(cd "$output" && /usr/bin/shasum -a 256 "$name.dmg" "$name.zip" > "$name.sha256")
printf 'Package (%s signature, NOT Apple notarized):\n%s\n%s\n' "$lane" "$output/$name.dmg" "$output/$name.zip"
