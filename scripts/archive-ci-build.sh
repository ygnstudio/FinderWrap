#!/bin/bash
# A deliberately unsigned verification artifact, never an installation package.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-minimum-system.py build/Products/Release/FinderWrap.app
mkdir -p build/ci
stage=$(mktemp -d "$PWD/build/ci/stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto --norsrc --noextattr build/Products/Release/FinderWrap.app "$stage/FinderWrap.app"
/usr/bin/xcrun strip -S "$stage/FinderWrap.app/Contents/MacOS/FinderWrap"
if /usr/bin/codesign --display "$stage/FinderWrap.app" >/dev/null 2>&1; then
    /usr/bin/codesign --remove-signature "$stage/FinderWrap.app"
fi
cat > "$stage/VERIFICATION-ONLY.txt" <<'TEXT'
Unsigned CI verification build. Do not install over your working FinderWrap.
Installation packages require the fixed certificate pinned in config/signing.json.
No permissions, signing identity, or notarization are provided by this archive.
TEXT
/usr/bin/ditto --norsrc --noextattr -c -k "$stage" build/ci/FinderWrap-verification-unsigned.zip
(cd build/ci && /usr/bin/shasum -a 256 FinderWrap-verification-unsigned.zip > SHA256SUMS)
