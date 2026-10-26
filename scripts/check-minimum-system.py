#!/usr/bin/env python3
"""Require Apple Silicon and macOS 13 in both manifest and binary; never launch."""
import pathlib
import plistlib
import re
import subprocess
import sys


def check(app, expected="13.0"):
    app = pathlib.Path(app)
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info.get("LSMinimumSystemVersion") != expected:
        raise ValueError("Info.plist minimum system version does not match " + expected)
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(binary)], text=True).split()
    if architectures != ["arm64"]:
        raise ValueError("Distribution requires Apple Silicon (arm64) only")
    for architecture in ("arm64",):
        output = subprocess.check_output(
            ["/usr/bin/otool", "-arch", architecture, "-l", str(binary)], text=True)
        versions = re.findall(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (?:1|MACOS)\s+minos ([\d.]+)", output)
        if versions != [expected]:
            raise ValueError(architecture + " Mach-O minimum system version does not match " + expected)
        print(architecture + ": macOS " + expected)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: check-minimum-system.py FinderWrap.app")
    try:
        check(sys.argv[1])
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
