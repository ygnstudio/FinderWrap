#!/usr/bin/env python3
"""Pin distribution identity. No key export, certificate creation, or trust changes."""
import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def policy():
    value = json.loads((ROOT / "config/signing.json").read_text())
    if value.get("bundleIdentifier") != "dev.finderwrap.finderwrap":
        raise ValueError("Unexpected bundle identifier in signing policy")
    for key, size in (("certificateSHA1", 40), ("certificateSHA256", 64)):
        if not isinstance(value.get(key), str) or not re.fullmatch(r"[A-Fa-f0-9]{%d}" % size, value[key]):
            raise ValueError("Fixed signing certificate is not configured; see docs/signing.md")
        value[key] = value[key].upper()
    return value


def requirement(value):
    # A certificate clause is essential: an identifier-only DR would be forgeable.
    return 'identifier "%s" and certificate leaf = H"%s"' % (
        value["bundleIdentifier"], value["certificateSHA1"])


def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def verify(app, value):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info["CFBundleIdentifier"] != value["bundleIdentifier"]:
        raise ValueError("Package bundle identifier differs from the fixed identity")
    req = requirement(value)
    signatures = []
    for arch in ("arm64", "x86_64"):
        run("/usr/bin/codesign", "--verify", "--strict", "--arch", arch, "-R", "=" + req, str(app))
        with tempfile.TemporaryDirectory(prefix="finderwrap-cert-") as directory:
            prefix = str(Path(directory) / "certificate")
            run("/usr/bin/codesign", "--display", "--arch", arch, "--extract-certificates=" + prefix, str(app))
            cert = Path(prefix + "0").read_bytes()
        if hashlib.sha256(cert).hexdigest().upper() != value["certificateSHA256"]:
            raise ValueError("Signed leaf certificate does not match the pinned SHA-256")
        if hashlib.sha1(cert).hexdigest().upper() != value["certificateSHA1"]:
            raise ValueError("Signed leaf certificate does not match the pinned SHA-1")
        designated = run("/usr/bin/codesign", "--display", "--arch", arch, "-r-", str(app)).decode().strip()
        expected = "designated => " + req
        if designated.lower() != expected.lower():
            raise ValueError("Designated requirement drift: " + designated)
        signatures.append({"architecture": arch, "designatedRequirement": designated})
    return {"bundleIdentifier": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"], "certificateSHA256": value["certificateSHA256"],
            "notarized": False, "signatures": signatures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("identity", "requirement", "verify"))
    parser.add_argument("app", nargs="?", type=Path)
    args = parser.parse_args()
    try:
        value = policy()
        if args.command == "identity":
            print(value["certificateSHA1"])
        elif args.command == "requirement":
            print("designated => " + requirement(value))
        elif args.app:
            print(json.dumps(verify(args.app, value), indent=2))
        else:
            parser.error("verify requires an app path")
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, "Signing verification failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
