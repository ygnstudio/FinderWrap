#!/bin/bash
# Moves the app to Trash, keeps preferences and never edits TCC or login items.
set -euo pipefail
apply=false
if [[ "${1:-}" == '--apply' ]]; then apply=true; shift; fi
app="${1:-$HOME/Applications/FinderWrap.app}"
[[ $# -le 1 && "$app" == /*/FinderWrap.app && -d "$app" && ! -L "$app" ]] || { echo 'Usage: uninstall.sh [--apply] [/absolute/path/FinderWrap.app]' >&2; exit 2; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == 'dev.finderwrap.finderwrap' ]] || exit 2
printf 'Move %s to Trash. First turn off Login at launch in FinderWrap and quit it.\n' "$app"
$apply || { echo 'Dry run. Add --apply after disabling login and quitting the app.'; exit 0; }
if /usr/bin/pgrep -x FinderWrap >/dev/null; then echo 'FinderWrap is running; quit it first.' >&2; exit 2; fi
trash_app="$HOME/.Trash/FinderWrap-$(date +%Y%m%d-%H%M%S).app"
[[ -d "$HOME/.Trash" && ! -e "$trash_app" ]] || exit 2
/bin/mv "$app" "$trash_app"
echo 'Moved to Trash. Preferences and system permission records were preserved.'
