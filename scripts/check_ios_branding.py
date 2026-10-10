#!/usr/bin/env python3
"""Verify localized iOS app/extension names before producing an install build."""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path


NAMES = {
    "en": "Recipe Pals",
    "zh-Hans": "私人菜谱",
    "zh-Hant": "私人菜譜",
    "ja": "Recipe Pals",
}
BUNDLES = (
    ("ios/Recipe/Info.plist", "ios/Recipe/Resources/InfoPlist.xcstrings"),
    ("ios/ShareExtension/Info.plist", "ios/ShareExtension/InfoPlist.xcstrings"),
)
BUNDLE_NAME_KEYS = ("CFBundleDisplayName", "CFBundleName")


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    for plist_path, catalog_path in BUNDLES:
        with (root / plist_path).open("rb") as file:
            info = plistlib.load(file)
        with (root / catalog_path).open(encoding="utf-8") as file:
            catalog = json.load(file)

        for key in BUNDLE_NAME_KEYS:
            if info.get(key) != NAMES["en"]:
                errors.append(f"{plist_path}: {key} must be {NAMES['en']!r}")
            localizations = catalog.get("strings", {}).get(key, {}).get("localizations", {})
            for locale, expected in NAMES.items():
                localization = localizations.get(locale, {})
                unit = localization.get("stringUnit", {}) if isinstance(localization, dict) else {}
                if not isinstance(unit, dict):
                    unit = {}
                actual = unit.get("value")
                if actual != expected:
                    errors.append(f"{catalog_path}: {key}[{locale}] is {actual!r}; expected {expected!r}")
                elif unit.get("state") != "translated":
                    state = unit.get("state")
                    errors.append(
                        f"{catalog_path}: {key}[{locale}] state is {state!r}; "
                        "expected 'translated'"
                    )

    return errors


def main() -> int:
    if len(sys.argv) > 2:
        print("Usage: check_ios_branding.py [repository-root]", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parent.parent
    errors = validate(root)
    if errors:
        print("iOS bundle branding check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("iOS app and Share Extension bundle names match Recipe Pals in all four locales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
