#!/usr/bin/env python3
"""Read-only ControlCenter diagnosis. Never changes preferences or permissions.

Run this yourself in a terminal that macOS already permits to read the file, or
pass an explicitly exported plist with --source. Output only matching records;
it may include local application paths, so keep it in ignored build/.
"""
import argparse
import json
import plistlib
from pathlib import Path


def decode(value):
    if isinstance(value, bytes):
        for parser in (plistlib.loads, json.loads):
            try:
                return decode(parser(value))
            except (ValueError, TypeError, plistlib.InvalidFileException):
                pass
        return {"undecodedBytes": len(value)}
    if isinstance(value, dict):
        return {str(k): decode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decode(v) for v in value]
    return value


def matching_records(value, target, location="trackedApplications"):
    if isinstance(value, dict):
        # Keep the owner and its isAllowed state together with matching locations.
        if "isAllowed" in value:
            if target.casefold() in (location + json.dumps(value, ensure_ascii=False, default=str)).casefold():
                yield {"location": location, "record": value}
            return
        for key, child in value.items():
            yield from matching_records(child, target, f"{location}/{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from matching_records(child, target, f"{location}/{index}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path.home() / "Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist")
    parser.add_argument("--target", default="finderwrap")
    args = parser.parse_args()
    try:
        outer = plistlib.loads(args.source.read_bytes())
    except PermissionError:
        print(json.dumps({"readSucceeded": False, "error": "macOS denied access; no settings changed"}))
        return 2
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(json.dumps({"readSucceeded": False, "error": type(error).__name__}))
        return 2
    if "trackedApplications" not in outer:
        print(json.dumps({"readSucceeded": True, "schemaRecognized": False, "reason": "trackedApplications absent"}))
        return 3
    tracked = decode(outer["trackedApplications"])
    matches = list(matching_records(tracked, args.target))
    result = {
        "readSucceeded": True,
        "target": args.target,
        "matchingRecords": matches,
        "note": "A foreign isAllowed=false record containing the target in menuItemLocations is evidence of a conflicting association; a hidden item alone is not.",
    }
    # Preserve relevant diagnostics if this OS uses another record schema.
    if not matches and args.target.casefold() in json.dumps(tracked, default=str).casefold():
        result["schemaRecognized"] = False
        result["reason"] = "Target is present but isAllowed record boundary was not recognized"
    print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
