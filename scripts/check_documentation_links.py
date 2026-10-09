#!/usr/bin/env python3
"""Check tracked Markdown links against local tracked repository files.

This is deliberately offline: external URLs, issue state, and anchor targets are
not verified. Run from the repository root with python3 scripts/check_documentation_links.py.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
MARKDOWN = re.compile(r"\.md$", re.IGNORECASE)
SKIP = ("https:", "http:", "mailto:", "tel:", "data:", "#", "<")


def tracked_paths(root: Path) -> list[Path]:
    try:
        files = subprocess.check_output(
            ["git", "-C", str(root), "ls-files", "-z"], stderr=subprocess.DEVNULL
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        raise RuntimeError("Run this check inside a Git repository.")
    return [root / unquote(name.decode("utf-8")) for name in files.split(b"\0") if name]


def broken_links(root: Path, files: list[Path]) -> list[str]:
    tracked = {path.resolve() for path in files}
    errors: list[str] = []
    for path in files:
        if not MARKDOWN.search(path.name):
            continue
        text = path.read_text(encoding="utf-8")
        for match in LINK.finditer(text):
            target = match.group(1).strip().split(' "', 1)[0].strip()
            if not target or target.startswith(SKIP) or "://" in target:
                continue
            relative = urlsplit(target).path
            if not relative:
                continue
            try:
                resolved = (path.parent / unquote(relative)).resolve()
            except (ValueError, OSError):
                continue
            if resolved in tracked or any(
                candidate in tracked
                for candidate in (resolved / "README.md", resolved / "index.md")
            ):
                continue
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"{path.relative_to(root)}:{line}: missing {relative}")
    return errors


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    try:
        files = tracked_paths(root)
        errors = broken_links(root, files)
    except (RuntimeError, UnicodeDecodeError) as error:
        print(error, file=sys.stderr)
        return 2
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"Documentation link check failed: {len(errors)} invalid target(s).", file=sys.stderr)
        return 1
    print("Documentation link check passed (tracked local relative targets only).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
