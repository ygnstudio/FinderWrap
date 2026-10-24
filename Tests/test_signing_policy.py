"""Distribution guard tests: no certificate/keychain access or system input."""
import importlib.util
import json
import os
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

    def test_untrusted_ci_events_rejected_before_accessing_secrets(self):
        for event, ref in (("pull_request", "refs/heads/main"), ("push", "refs/heads/feature"),
                           ("workflow_dispatch", "refs/tags/v1.0.1")):
            with self.subTest(event=event, ref=ref):
                result = subprocess.run(["bash", "scripts/ci-sign-package.sh"], cwd=ROOT,
                                        env={**os.environ, "GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": event,
                                             "GITHUB_REF": ref}, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
