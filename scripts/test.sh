#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
xcodebuild -project FinderWrap.xcodeproj -scheme FinderWrap \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$PWD/build/DerivedData" CODE_SIGNING_ALLOWED=NO test \
    >build/logs/tests.log 2>&1 || { tail -100 build/logs/tests.log >&2; exit 1; }
tail -30 build/logs/tests.log
