#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --package-path Rebuild --scratch-path "$PWD/build/Tests"
python3 -m unittest discover -s Tests -p 'test_*.py' -v
