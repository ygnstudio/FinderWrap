#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo 'Usage: scripts/build.sh [Debug|Release]' >&2; exit 2 ;; esac
mkdir -p build/logs
for scheme in FinderWrap FinderAXProbe; do
    xcodebuild -project FinderWrap.xcodeproj -scheme "$scheme" \
        -configuration "$configuration" -destination 'platform=macOS' \
        -derivedDataPath "$PWD/build/DerivedData" CODE_SIGNING_ALLOWED=NO build \
        >"build/logs/${scheme}-${configuration}.log" 2>&1 || {
            tail -80 "build/logs/${scheme}-${configuration}.log" >&2
            exit 1
        }
    echo "$scheme $configuration built (unsigned)."
done
