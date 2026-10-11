# Developer: gengyun
# Purpose: Reject actual copied-release tampering and path escape without network or database access.

import json
from pathlib import Path
import shutil
import tempfile
import unittest

from verify_release import verify_release


class ReleaseIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repository"
        self.module = self.root / "supabase/functions/revenuecat-webhook"
        original = Path(__file__).resolve().parents[4]
        source = original / "supabase/functions/revenuecat-webhook"
        self.module.mkdir(parents=True)
        self.manifest_path = self.module / "release.json"
        self.manifest = json.loads((source / "release.json").read_text())
        shutil.copyfile(source / "release.json", self.manifest_path)
        for name in self.manifest["source_sha256"]:
            shutil.copyfile(source / name, self.module / name)
        migration = self.manifest["required_migration"]["path"]
        destination = self.root / migration
        destination.parent.mkdir(parents=True)
        shutil.copyfile(original / migration, destination)

    def save_manifest(self):
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")

    def test_actual_release_copy_matches(self):
        self.assertEqual(verify_release(self.root), 5)

    def test_actual_source_and_migration_byte_changes_fail(self):
        for path in (self.module / "webhook.ts", self.root / self.manifest["required_migration"]["path"]):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_bytes(original + b"\nmodified\n")
                with self.assertRaisesRegex(ValueError, "mismatch"):
                    verify_release(self.root)
                path.write_bytes(original)

    def test_missing_file_fails(self):
        (self.module / "deno.lock").unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            verify_release(self.root)

    def test_malformed_or_incomplete_manifest_fails(self):
        for content in ("{", "null", "[]", "{}"):
            with self.subTest(content=content):
                self.manifest_path.write_text(content)
                with self.assertRaises(ValueError):
                    verify_release(self.root)

    def test_invalid_hash_and_missing_required_hash_fail(self):
        self.manifest["source_sha256"]["index.ts"] = "not-a-sha256"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "Invalid SHA"):
            verify_release(self.root)
        del self.manifest["source_sha256"]["index.ts"]
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "Missing hashed entrypoint"):
            verify_release(self.root)

    def test_traversal_absolute_and_backslash_paths_fail(self):
        for name in ("../outside.ts", "/tmp/outside.ts", "..\\outside.ts"):
            with self.subTest(name=name):
                self.manifest["source_sha256"][name] = "a" * 64
                self.save_manifest()
                with self.assertRaises(ValueError):
                    verify_release(self.root)
                del self.manifest["source_sha256"][name]
        self.manifest["required_migration"]["path"] = "../outside.sql"
        self.save_manifest()
        with self.assertRaises(ValueError):
            verify_release(self.root)

    def test_source_and_migration_symlink_escape_fail(self):
        outside = Path(self.temporary.name) / "outside"
        for path in (self.module / "index.ts", self.root / self.manifest["required_migration"]["path"]):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                outside.write_bytes(original)  # Even identical bytes outside the root are rejected.
                path.unlink()
                path.symlink_to(outside)
                with self.assertRaisesRegex(ValueError, "escaped"):
                    verify_release(self.root)
                path.unlink()
                path.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
