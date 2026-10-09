#!/usr/bin/env python3
"""Reject obsolete RecipePouch copy in iOS UI, localization, and regression tests."""

from __future__ import annotations

import sys
from pathlib import Path


# Legacy persistence signatures and diagnostic domains are not display strings.
LEGACY_EXCEPTIONS = {
    "ios/RecipeCore/Sources/RecipeCore/RecipeLocalEraseMarker.swift": (
        'private static let signature = Data("RecipePouch.localErasePending.v1".utf8)',
    ),
    "ios/ShareExtension/ShareViewController.swift": (
        'domain: "RecipePouch.ShareExtension",',
    ),
}


def inspect(root: Path) -> list[str]:
    errors: list[str] = []
    paths = list((root / "ios").rglob("*.swift"))
    paths.extend((root / "ios").rglob("*.xcstrings"))
    paths.extend((root / "ios").rglob("*.strings"))

    for path in paths:
        relative = path.relative_to(root).as_posix()
        exceptions = LEGACY_EXCEPTIONS.get(relative, ())
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "RecipePouch" in line and not any(exception in line for exception in exceptions):
                errors.append(f"{relative}:{number}: legacy user-visible name")
    return errors


def main() -> int:
    if len(sys.argv) > 2:
        print("Usage: check_ios_public_brand.py [repository-root]", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parent.parent
    errors = inspect(root)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("iOS user-facing copy consistently uses Recipe Pals; legacy technical IDs preserved.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
