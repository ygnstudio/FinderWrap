"""Distribution guard tests: no certificate/keychain access or system input."""
import importlib.util
import hashlib
import json
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("signing_policy", ROOT / "scripts/signing-policy.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningPolicyTests(unittest.TestCase):
    def load(self, value):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config").mkdir()
            (root / "config/signing.json").write_text(json.dumps(value))
            with patch.object(signing, "ROOT", root):
                return signing.policy()

    def test_unconfigured_certificate_fails_closed(self):
        with self.assertRaises(ValueError):
            self.load({"bundleIdentifier": "dev.finderwrap.finderwrap", "certificateSHA1": None,
                       "certificateSHA256": None})

    def test_certificate_pin_is_required_in_designated_requirement(self):
        value = self.load({"bundleIdentifier": "dev.finderwrap.finderwrap", "certificateSHA1": "a" * 40,
                           "certificateSHA256": "b" * 64})
        self.assertEqual(signing.requirement(value),
                         'identifier "dev.finderwrap.finderwrap" and certificate leaf = H"' + "A" * 40 + '"')

    def test_wrong_identifier_and_malformed_pins_are_rejected(self):
        valid = {"bundleIdentifier": "dev.finderwrap.finderwrap", "certificateSHA1": "a" * 40,
                 "certificateSHA256": "b" * 64}
        for key, bad in (("bundleIdentifier", "another.app"), ("certificateSHA1", "-"),
                         ("certificateSHA1", '" or true'), ("certificateSHA256", "ab")):
            with self.subTest(key=key, bad=bad), self.assertRaises(ValueError):
                self.load({**valid, key: bad})

    def test_ci_rejects_ad_hoc_package_before_touching_outputs(self):
        result = subprocess.run(["bash", "scripts/package.sh", "--ad-hoc"], cwd=ROOT,
                                env={**os.environ, "CI": "true"}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("forbidden in CI", result.stderr)

    def test_install_requires_an_explicit_fixed_signed_package(self):
        result = subprocess.run(["bash", "scripts/install.sh"], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("fixed-signed", result.stderr)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source/FinderWrap.app"
            destination = Path(directory) / "destination/FinderWrap.app"
            (source / "Contents").mkdir(parents=True)
            (source / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "dev.finderwrap.finderwrap", "CFBundleExecutable": "FinderWrap",
                "LSMinimumSystemVersion": "13.0"}))
            result = subprocess.run(["bash", "scripts/install.sh", "--apply", str(source), str(destination)],
                                    cwd=ROOT, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(destination.exists())

    def test_untrusted_ci_events_rejected_before_accessing_secrets(self):
        for event, ref in (("pull_request", "refs/heads/main"), ("push", "refs/heads/feature"),
                           ("workflow_dispatch", "refs/tags/v1.0.1")):
            with self.subTest(event=event, ref=ref):
                result = subprocess.run(["bash", "scripts/ci-sign-package.sh"], cwd=ROOT,
                                        env={**os.environ, "GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": event,
                                             "GITHUB_REF": ref}, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)

    def test_arm64_verification_preserves_certificate_and_designated_requirement(self):
        cert = b"public-test-certificate"
        value = {"bundleIdentifier": "dev.finderwrap.finderwrap",
                 "certificateSHA1": hashlib.sha1(cert).hexdigest().upper(),
                 "certificateSHA256": hashlib.sha256(cert).hexdigest().upper()}
        calls = []

        def run(*args):
            calls.append(args)
            if args[0].endswith("lipo"):
                return b"arm64\n"
            for arg in args:
                if arg.startswith("--extract-certificates="):
                    Path(arg.split("=", 1)[1] + "0").write_bytes(cert)
            if "-r-" in args:
                return ("designated => " + signing.requirement(value)).encode()
            return b""

        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "FinderWrap.app"
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": value["bundleIdentifier"], "CFBundleExecutable": "FinderWrap",
                "CFBundleShortVersionString": "1.0.3", "CFBundleVersion": "6"}))
            with patch.object(signing, "run", run):
                result = signing.verify(app, value)
            self.assertEqual([item["architecture"] for item in result["signatures"]], ["arm64"])
            self.assertTrue(any("-R" in call and "=" + signing.requirement(value) in call for call in calls))
            with patch.object(signing, "run", return_value=b"arm64 x86_64\n") as runner:
                with self.assertRaisesRegex(ValueError, "arm64.*only"):
                    signing.verify(app, value)
                self.assertEqual(runner.call_count, 1, "Architecture mismatch must stop before certificate access")


if __name__ == "__main__":
    unittest.main()
