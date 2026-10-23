#!/usr/bin/env python3
"""Local repair for the observed FinderWrap/Codex menu registration collision.

Dry run by default. --apply removes only FinderWrap's location from the hidden
Codex record, preserving Codex's visibility and every other app association.
Requires the user to run it in a terminal macOS permits to access this plist.
This is a one-machine repair tool, not part of FinderWrap or its installer.
"""
import argparse
import copy
import datetime
import json
import os
import plistlib
import subprocess
from pathlib import Path

TARGET = "dev.finderwrap.finderwrap"
OWNER = "com.openai.codex"
SOURCE = Path.home() / "Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"


def patch_tracking(value):
    new = copy.deepcopy(value)
    removed = 0

    def visit(node):
        nonlocal removed
        if isinstance(node, dict):
            if "isAllowed" in node:
                if node.get("location") == {"bundle": {"_0": OWNER}} and node["isAllowed"] is False:
                    locations = node.get("menuItemLocations")
                    if not isinstance(locations, list):
                        raise ValueError("Unexpected menuItemLocations schema; no changes made")
                    keep = [item for item in locations if item != {"bundle": {"_0": TARGET}}]
                    removed += len(locations) - len(keep)
                    node["menuItemLocations"] = keep
                return
            for child in node.values():
                visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)

    visit(new)
    if removed != 1:
        raise ValueError(f"Expected exactly one known conflicting association, found {removed}; no changes made")
    return new


def decode_tracking(raw):
    if not isinstance(raw, bytes):
        return raw, lambda value: value
    if raw.startswith((b"bplist", b"<?xml")):
        fmt = plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML
        return plistlib.loads(raw), lambda value: plistlib.dumps(value, fmt=fmt, sort_keys=False)
    return json.loads(raw), lambda value: json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if SOURCE.is_symlink() or SOURCE.stat().st_uid != os.getuid():
        raise ValueError("Unexpected preference file owner or symlink; no changes made")
    original = SOURCE.read_bytes()
    outer = plistlib.loads(original)
    tracked, encode = decode_tracking(outer["trackedApplications"])
    patched = patch_tracking(tracked)
    print(f"Remove only {TARGET} from {OWNER}'s menuItemLocations; keep isAllowed=false and other locations.")
    if not args.apply:
        print("Dry run. Add --apply to save a backup and apply this exact repair.")
        return
    if subprocess.run(["/usr/bin/pgrep", "-x", "FinderWrap"], capture_output=True).returncode == 0:
        raise ValueError("Quit FinderWrap first; no changes made")
    folder = Path(__file__).resolve().parent.parent / "build/menubar-backups" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    folder.mkdir(parents=True, mode=0o700)
    backup = folder / "controlcenter-before.plist"
    with backup.open("xb") as stream:
        os.chmod(backup, 0o600)
        stream.write(original)
    changed = copy.deepcopy(outer)
    changed["trackedApplications"] = encode(patched)
    if SOURCE.read_bytes() != original:
        raise ValueError("Preferences changed while preparing repair; backup saved, no changes applied")
    # defaults updates the preference service. No daemon-wide cache deletion.
    subprocess.run(["/usr/bin/defaults", "import", str(SOURCE.with_suffix("")), "-"],
                   input=plistlib.dumps(changed, sort_keys=False), check=True)
    actual = plistlib.loads(SOURCE.read_bytes())
    verified, _ = decode_tracking(actual["trackedApplications"])
    other_keys_unchanged = {k: v for k, v in actual.items() if k != "trackedApplications"} == {k: v for k, v in outer.items() if k != "trackedApplications"}
    if verified != patched or not other_keys_unchanged:
        raise ValueError(f"Readback differs; stop and inspect. Backup: {backup}")
    print("Verified: only the intended association was removed. All other preference values are unchanged.")
    print(f"Backup: {backup}")
    print("Relaunch FinderWrap from Finder, then check its own menu bar visibility setting.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Stopped: {error}")
