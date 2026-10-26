#!/bin/bash
# Default is a dry run; running with --apply is an explicit user action.
set -euo pipefail
cd "$(dirname "$0")/.."
apply=false
if [[ "${1:-}" == '--apply' ]]; then apply=true; shift; fi
source_app="${1:-}"
destination="${2:-$HOME/Applications/FinderWrap.app}"
[[ $# -ge 1 && $# -le 2 && -d "$source_app" && ! -L "$source_app" ]] || { echo 'Usage: install.sh [--apply] /path/to/fixed-signed/FinderWrap.app [destination/FinderWrap.app]' >&2; exit 2; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$source_app/Contents/Info.plist")" == 'dev.finderwrap.finderwrap' ]] || exit 2
python3 scripts/check-minimum-system.py "$source_app"
python3 scripts/signing-policy.py verify "$source_app" >/dev/null
[[ "$destination" == /*/FinderWrap.app && ! -e "$destination" && ! -L "$destination" ]] || { echo 'Destination must be a new absolute FinderWrap.app path; existing apps are never overwritten.' >&2; exit 2; }
printf 'Copy %s to %s\n' "$source_app" "$destination"
$apply || { echo 'Dry run. Add --apply to copy. No launch, login registration or permission changes.'; exit 0; }
mkdir -p "$(dirname "$destination")"
stage=$(mktemp -d "$(dirname "$destination")/.finderwrap-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$source_app" "$stage/FinderWrap.app"
python3 scripts/signing-policy.py verify "$stage/FinderWrap.app" >/dev/null
[[ ! -e "$destination" && ! -L "$destination" ]] || exit 2
/bin/mv "$stage/FinderWrap.app" "$destination"
python3 scripts/signing-policy.py verify "$destination" >/dev/null
echo 'Installed fixed-signature app. Open it and grant the permissions you choose. Navigation starts paused.'
