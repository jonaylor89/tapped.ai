"""Exercise the Xcode Cloud hook without network access or real credentials."""

import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tarfile
import tempfile
import unittest


@unittest.skipUnless(sys.platform == "darwin", "Hook uses macOS PlistBuddy")
class PostHogSymbolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="posthog-symbols-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.archive = self.root / "archive with spaces.xcarchive"
        (self.archive / "dSYMs/Tapped.app.dSYM").mkdir(parents=True)
        self.metadata = {
            "CFBundleIdentifier": "com.intheloopstudio",
            "CFBundleShortVersionString": "8.9.10",
            "CFBundleVersion": "431",
        }
        self.write_metadata()
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            TMPDIR=str(self.root),
            CI_XCODEBUILD_ACTION="archive",
            CI_XCODEBUILD_EXIT_CODE="0",
            CI_ARCHIVE_PATH=str(self.archive),
            POSTHOG_CLI_API_KEY="test-placeholder-not-a-real-key",
            TEST_ROOT=str(self.root),
        )
        # A local fake release archive: the test never downloads or executes remote code.
        cli = b'''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ["--version"]:
    print("posthog-cli " + os.environ.get("TEST_CLI_VERSION", "0.18.10"))
else:
    with open(os.environ["TEST_ROOT"] + "/upload.json", "w") as f:
        json.dump({"args": sys.argv[1:], "host": os.environ["POSTHOG_CLI_HOST"],
                   "project": os.environ["POSTHOG_CLI_PROJECT_ID"]}, f)
    sys.exit(int(os.environ.get("TEST_UPLOAD_EXIT", "0")))
'''
        with tarfile.open(self.root / "fixture.tar.gz", "w:gz") as archive:
            entry = tarfile.TarInfo("release/posthog-cli")
            entry.size = len(cli)
            entry.mode = 0o755
            archive.addfile(entry, io.BytesIO(cli))
        self.stub("uname", 'echo "${TEST_ARCH:-arm64}"')
        self.stub("curl", '''
          printf '%s\n' "$@" > "$TEST_ROOT/download-args"
          [[ "${TEST_DOWNLOAD_FAIL:-0}" == 0 ]] || exit 22
          while [[ "$1" != --output ]]; do shift; done
          cp "$TEST_ROOT/fixture.tar.gz" "$2"
        ''')
        self.stub("shasum", '''
          [[ "$*" == '-a 256 -c -' ]]
          read -r hash path
          [[ "$hash" =~ ^[a-f0-9]{64}$ && -f "$path" ]]
          [[ "${TEST_CHECKSUM_FAIL:-0}" == 0 ]]
        ''')
        self.stub("xcrun", '''
          [[ "${TEST_DWARFDUMP_FAIL:-0}" == 0 ]] || exit 1
          [[ "${TEST_EMPTY_UUID:-0}" == 0 ]] || exit 0
          uuid=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
          if [[ "${TEST_MISMATCH:-0}" == 1 && "$*" == *dSYM* ]]; then uuid=OTHER; fi
          echo "UUID: $uuid (arm64) $*"
        ''')

    def write_metadata(self):
        (self.archive / "Info.plist").write_bytes(plistlib.dumps({"ApplicationProperties": self.metadata}))

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)

    def run_hook(self, expected_success=True, **env):
        script = Path(__file__).resolve().parents[1] / "ci_post_xcodebuild.sh"
        result = subprocess.run([str(script)], env=self.env | env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, expected_success, result.stdout + result.stderr)
        self.assertNotIn(self.env["POSTHOG_CLI_API_KEY"], result.stdout + result.stderr)
        self.assertEqual(list(self.root.glob("tapped-posthog-cli.*")), [], "CLI temp directory leaked")
        return result

    def test_skips_non_archive_and_failed_actions_without_credentials(self):
        for action, status in [("test-without-building", "0"), ("build", "0"), ("archive", "65"), ("archive", "")]:
            with self.subTest(action=action, status=status):
                self.run_hook(CI_XCODEBUILD_ACTION=action, CI_XCODEBUILD_EXIT_CODE=status, POSTHOG_CLI_API_KEY="")
        self.assertFalse((self.root / "download-args").exists())

    def test_success_reads_actual_archive_metadata_on_both_architectures(self):
        for arch, target in [("arm64", "aarch64"), ("x86_64", "x86_64")]:
            with self.subTest(arch=arch):
                self.run_hook(TEST_ARCH=arch)
                upload = json.loads((self.root / "upload.json").read_text())
                self.assertEqual(upload, {
                    "host": "https://us.posthog.com", "project": "75329",
                    "args": ["dsym", "upload", "--directory", str(self.archive / "dSYMs"),
                             "--main-dsym", "Tapped.app.dSYM", "--release-name", "com.intheloopstudio",
                             "--release-version", "8.9.10", "--build", "431"],
                })
                self.assertIn(f"v0.18.10/posthog-cli-{target}-apple-darwin.tar.gz",
                              (self.root / "download-args").read_text())

    def test_missing_secret_or_archive_path_fails_before_download(self):
        for name in ["POSTHOG_CLI_API_KEY", "CI_ARCHIVE_PATH"]:
            with self.subTest(name=name):
                self.run_hook(False, **{name: ""})
        self.assertFalse((self.root / "download-args").exists())

    def test_missing_main_dsym_fails(self):
        (self.archive / "dSYMs/Tapped.app.dSYM").rmdir()
        self.run_hook(False)

    def test_wrong_app_or_missing_version_metadata_fails(self):
        for key, value in [
            ("CFBundleIdentifier", "other.app"),
            ("CFBundleShortVersionString", ""),
            ("CFBundleVersion", ""),
        ]:
            with self.subTest(key=key):
                original = self.metadata[key]
                self.metadata[key] = value
                self.write_metadata()
                self.run_hook(False)
                self.metadata[key] = original
        self.assertFalse((self.root / "download-args").exists())

    def test_missing_mismatched_or_unreadable_uuids_fail(self):
        for name in ["TEST_MISMATCH", "TEST_EMPTY_UUID", "TEST_DWARFDUMP_FAIL"]:
            with self.subTest(name=name):
                self.run_hook(False, **{name: "1"})
        self.assertFalse((self.root / "download-args").exists())

    def test_unsupported_architecture_fails_before_download(self):
        self.run_hook(False, TEST_ARCH="unsupported")
        self.assertFalse((self.root / "download-args").exists())

    def test_install_and_upload_errors_fail_and_clean_up(self):
        for env in [{"TEST_DOWNLOAD_FAIL": "1"}, {"TEST_CHECKSUM_FAIL": "1"},
                    {"TEST_CLI_VERSION": "0.0.0"}, {"TEST_UPLOAD_EXIT": "1"}]:
            with self.subTest(env=env):
                self.run_hook(False, **env)


if __name__ == "__main__":
    unittest.main()
