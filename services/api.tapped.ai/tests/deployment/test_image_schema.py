import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
GUARD = ROOT / "scripts/check-image-schema.sh"


class ImageSchemaTests(unittest.TestCase):
    def check(self, version, bundle="20261030000000", epoch="20261024010000", datastore="postgres"):
        with tempfile.TemporaryDirectory() as directory:
            docker = Path(directory) / "docker"
            docker.write_text("""#!/bin/bash
set -eu
if [[ "$1" == exec ]]; then printf '%s\\n' "$TEST_VERSION";
elif [[ "$*" == *io.tapped.datastore* ]]; then printf '%s\\n' "$TEST_DATASTORE";
elif [[ "$*" == *io.tapped.schema_epoch* ]]; then printf '%s\\n' "$TEST_EPOCH";
elif [[ "$*" == *io.tapped.migration_bundle* ]]; then printf '%s\\n' "$TEST_BUNDLE";
else exit 2; fi
""")
            docker.chmod(0o700)
            result = subprocess.run(
                ["bash", str(GUARD), "fixture:image"],
                env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"],
                     "TEST_VERSION": version, "TEST_BUNDLE": bundle,
                     "TEST_EPOCH": epoch, "TEST_DATASTORE": datastore},
                capture_output=True, text=True, check=False,
            )
            return result.returncode == 0

    def test_current_image_passes(self):
        self.assertTrue(self.check("20261030000000"))

    def test_missing_or_old_bundle_rejected_for_rollout_and_rollback(self):
        for bundle in ["", "<no value>", "20261027000000", "20261029000000", "not-a-version"]:
            with self.subTest(bundle=bundle):
                self.assertFalse(self.check("20261030000000", bundle=bundle))

    def test_future_database_requires_new_image(self):
        self.assertFalse(self.check("20261031000000"))

    def test_old_epoch_or_datastore_rejected(self):
        self.assertFalse(self.check("20261030000000", epoch="old"))
        self.assertFalse(self.check("20261030000000", datastore="firestore"))

    def test_pre_scraper_database_accepts_legacy_bundle(self):
        self.assertTrue(self.check("20261027000000", bundle=""))
        self.assertTrue(self.check("0", bundle=""))

    def test_malformed_ledger_rejected(self):
        for version in ["", "abc", "20261030000000;exit 0", "99999999999999999999"]:
            self.assertFalse(self.check(version))

    def test_docker_label_matches_highest_embedded_migration(self):
        latest = max(int(p.name.split("_", 1)[0]) for p in (ROOT / "migrations").glob("*.sql"))
        match = re.search(r'LABEL io\.tapped\.migration_bundle="(\d+)"', (ROOT / "Dockerfile").read_text())
        self.assertIsNotNone(match)
        self.assertEqual(latest, int(match.group(1)))


if __name__ == "__main__":
    unittest.main()
