#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
    -module-cache-path build/ModuleCache Tools/FinderAXProbe/SelectionCheck.swift \
    -o build/FinderAXSelectionCheck
exec ./build/FinderAXSelectionCheck
