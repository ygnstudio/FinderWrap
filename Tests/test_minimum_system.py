"""Manifest changes alone must not claim a compatible installation binary."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("minimum_system", Path(__file__).resolve().parent.parent / "scripts/check-minimum-system.py")
minimum = importlib.util.module_from_spec(spec)
spec.loader.exec_module(minimum)


class MinimumSystemTests(unittest.TestCase):
    def verify(self, *, manifest="13.0", architectures="arm64", binary="13.0"):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "FinderWrap.app"
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "FinderWrap", "LSMinimumSystemVersion": manifest}))
            output = "cmd LC_BUILD_VERSION\ncmdsize 32\nplatform 1\nminos " + binary + "\nsdk 27.0\n"
            with patch.object(minimum.subprocess, "check_output", side_effect=[architectures, output]):
                minimum.check(app)

    def test_apple_silicon_macos13_is_accepted(self):
        self.verify()

    def test_intel_and_universal_artifacts_are_rejected(self):
        for arch in ["x86_64", "arm64 x86_64", ""]:
            with self.subTest(arch=arch), self.assertRaisesRegex(ValueError, "arm64.*only"):
                self.verify(architectures=arch)

    def test_manifest_cannot_disguise_newer_binary(self):
        with self.assertRaisesRegex(ValueError, "Mach-O"):
            self.verify(binary="15.0")

    def test_manifest_must_also_match(self):
        with self.assertRaisesRegex(ValueError, "Info.plist"):
            self.verify(manifest="15.0")


if __name__ == "__main__":
    unittest.main()
