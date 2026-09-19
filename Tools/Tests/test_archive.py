"""Exercise release expectations against a complete minimal archive, without Xcode."""
import os
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class ArchiveContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mossling-archive-tests-")
        cls.root = pathlib.Path(cls.temporary.name)
        cls.checker = cls.root / "check-archive"
        subprocess.run(["swiftc", str(ROOT / "Tools/CheckArchive.swift"), "-o", str(cls.checker)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.case = tempfile.TemporaryDirectory(dir=self.root)
        self.archive = pathlib.Path(self.case.name) / "Mossling.xcarchive"
        self.phone = self.archive / "Products/Applications/Mossling.app"
        self.watch = self.phone / "Watch/MosslingWatch.app"
        for bundle, identifier, platform in [(self.phone, "com.joshrwolf.mossling", "iPhoneOS"),
                                             (self.watch, "com.joshrwolf.mossling.watchkitapp", "WatchOS")]:
            bundle.mkdir(parents=True)
            info = dict(CFBundleIdentifier=identifier, CFBundlePackageType="APPL",
                        CFBundleSupportedPlatforms=[platform], CFBundleExecutable="app",
                        CFBundleShortVersionString="0.1.0", CFBundleVersion="42")
            if bundle == self.watch:
                info["WKCompanionAppBundleIdentifier"] = "com.joshrwolf.mossling"
            self.write_plist(bundle / "Info.plist", info)
            self.write_plist(bundle / "PrivacyInfo.xcprivacy", {})
            (bundle / "Assets.car").write_bytes(b"fixture")
            (bundle / "app").write_bytes(b"fixture")
            (bundle / "app").chmod(0o755)
        self.write_plist(self.archive / "Info.plist", {"ApplicationProperties": {"ApplicationPath": "Applications/Mossling.app"}})

    def tearDown(self):
        self.case.cleanup()

    @staticmethod
    def write_plist(path, value):
        path.write_bytes(plistlib.dumps(value))

    def edit(self, bundle, key, value):
        path = bundle / "Info.plist"
        info = plistlib.loads(path.read_bytes())
        info[key] = value
        self.write_plist(path, info)

    def check(self, *extra):
        return subprocess.run([str(self.checker), str(self.archive), *extra], capture_output=True, text=True)

    def test_valid_unsigned_and_release_expectations(self):
        self.assertEqual(self.check().returncode, 0)
        result = self.check("--expect-bundle-id", "com.joshrwolf.mossling", "--expect-build-number", "42", "--expect-version", "0.1.0")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_matching_phone_watch_can_still_be_wrong_release(self):
        for flag, wrong in [("--expect-bundle-id", "com.other.mossling"), ("--expect-build-number", "43"), ("--expect-version", "0.2.0")]:
            with self.subTest(flag=flag):
                result = self.check(flag, wrong)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("expected release value", result.stderr)

    def test_watch_mismatch_rejected(self):
        self.edit(self.watch, "CFBundleVersion", "43")
        self.assertNotEqual(self.check().returncode, 0)

    def test_wrong_companion_rejected(self):
        self.edit(self.watch, "WKCompanionAppBundleIdentifier", "com.other.mossling")
        self.assertNotEqual(self.check().returncode, 0)

    def test_simulator_archive_rejected(self):
        self.edit(self.phone, "CFBundleSupportedPlatforms", ["iPhoneSimulator"])
        self.assertNotEqual(self.check().returncode, 0)

    def test_missing_watch_rejected(self):
        (self.watch / "Info.plist").unlink()
        self.assertNotEqual(self.check().returncode, 0)

    def test_malformed_expectations_rejected(self):
        for args in [("--unexpected", "a"), ("--expect-version",), ("--expect-version", ""),
                     ("--expect-version", "0.1.0", "--expect-version", "0.1.0")]:
            with self.subTest(args=args):
                self.assertNotEqual(self.check(*args).returncode, 0)

if __name__ == "__main__":
    unittest.main()
