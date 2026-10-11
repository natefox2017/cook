#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Verify checked-in source bytes against the existing webhook release manifest offline.

import hashlib
import json
from pathlib import Path
import re
import sys


def checked_path(root: Path, name: str) -> Path:
    """Reject traversal and symlink escape before reading manifest-controlled files."""
    if not isinstance(name, str) or not name or "\\" in name:
        raise ValueError("Invalid manifest file path")
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Manifest file path escapes its source root")
    resolved = (root / relative).resolve()
    if not resolved.is_relative_to(root.resolve()) or not resolved.is_file():
        raise ValueError(f"Missing or escaped manifest file: {name}")
    return resolved


def verify_release(repository: Path) -> int:
    module = repository / "supabase/functions/revenuecat-webhook"
    manifest_path = checked_path(repository, "supabase/functions/revenuecat-webhook/release.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("Release manifest must be an object")
    sources = manifest.get("source_sha256")
    migration = manifest.get("required_migration")
    if not isinstance(sources, dict) or not sources or not isinstance(migration, dict):
        raise ValueError("Missing source hashes or prerequisite migration")
    for field in ("entrypoint", "import_map"):
        if not isinstance(manifest.get(field), str) or manifest[field] not in sources:
            raise ValueError(f"Missing hashed {field}")
    if "deno.lock" not in sources:
        raise ValueError("Missing frozen dependency lock hash")
    if not isinstance(migration.get("path"), str) or "sha256" not in migration:
        raise ValueError("Missing prerequisite migration path or hash")
    checks = [(module, name, digest) for name, digest in sources.items()]
    checks.append((repository, migration["path"], migration["sha256"]))
    # Resolve and validate every path before reading any manifest-controlled bytes.
    files = []
    for root, name, expected in checks:
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError(f"Invalid SHA-256 for {name}")
        files.append((checked_path(root, name), name, expected))
    for path, name, expected in files:
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"Source SHA-256 mismatch: {name}")
    return len(files)


def main() -> int:
    repository = Path(__file__).resolve().parents[4]
    try:
        count = verify_release(repository)
    except (OSError, ValueError, TypeError) as error:
        print(f"FAIL source manifest: {error}", file=sys.stderr)
        return 1
    print(f"PASS source manifest: {count} file hashes match.")
    print("Bundle identity and deployed versions were NOT VERIFIED; no remote access or deployment performed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
