#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe="$PWD/build/DerivedData/Build/Products/Debug/FinderAXProbe"
if [[ ! -x "$probe" ]]; then
    echo 'Run bash scripts/build.sh Debug first.' >&2
    exit 2
fi
exec "$probe" "$@"
