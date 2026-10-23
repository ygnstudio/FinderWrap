#!/bin/bash
# Default is a dry run; running with --apply is an explicit user action.
set -euo pipefail
cd "$(dirname "$0")/.."
apply=false
if [[ "${1:-}" == '--apply' ]]; then apply=true; shift; fi
source_app="${1:-$PWD/build/DerivedData/Build/Products/Release/FinderWrap.app}"
destination="${2:-$HOME/Applications/FinderWrap.app}"
[[ $# -le 2 && -d "$source_app" && ! -L "$source_app" ]] || { echo 'Usage: install.sh [--apply] [source.app] [destination/FinderWrap.app]' >&2; exit 2; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$source_app/Contents/Info.plist")" == 'dev.finderwrap.finderwrap' ]] || exit 2
[[ "$destination" == /*/FinderWrap.app && ! -e "$destination" && ! -L "$destination" ]] || { echo 'Destination must be a new absolute FinderWrap.app path; existing apps are never overwritten.' >&2; exit 2; }
printf 'Copy %s to %s\n' "$source_app" "$destination"
$apply || { echo 'Dry run. Add --apply to copy. No launch, login registration or permission changes.'; exit 0; }
mkdir -p "$(dirname "$destination")"
/usr/bin/ditto "$source_app" "$destination"
echo 'Copied. Open the app yourself; grant only the permissions you choose. Login at launch stays optional.'
