#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Audit the completeness and interpolation safety of shipped Xcode String Catalogs.

"""Check translation coverage without requiring Xcode or external translation services.

Use --strict before an actual multilingual release. While a locale is being translated,
the default mode reports English fallbacks without failing the audit.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = (
    ("Recipe", ROOT / "ios/Recipe/Resources/Localizable.xcstrings"),
    ("Recipe InfoPlist", ROOT / "ios/Recipe/Resources/InfoPlist.xcstrings"),
    ("Share Extension", ROOT / "ios/ShareExtension/Localizable.xcstrings"),
    ("Share InfoPlist", ROOT / "ios/ShareExtension/InfoPlist.xcstrings"),
)
PLISTS = (
    ROOT / "ios/Recipe/Info.plist",
    ROOT / "ios/ShareExtension/Info.plist",
)
# Literal placeholders must be preserved in localized text, including plural forms.
PLACEHOLDER = re.compile(r"%(?:\\d+\\$)?(?:lld|llu|ld|lu|d|u|@|s|f|g)")


def placeholders(text: str) -> list[str]:
    return sorted(PLACEHOLDER.findall(text.replace("%%", "")))


def translated_units(localization: dict) -> list[str]:
    if "stringUnit" in localization:
        value = localization["stringUnit"]
        return [value["value"]] if value.get("state") == "translated" else []
    units: list[str] = []
    for choices in localization.get("variations", {}).values():
        for variant in choices.values():
            unit = variant.get("stringUnit", {})
            if unit.get("state") == "translated":
                units.append(unit["value"])
    return units


def run(strict: bool) -> int:
    languages_by_target: list[set[str]] = []
    for plist in PLISTS:
        with plist.open("rb") as input_file:
            languages_by_target.append(
                set(plistlib.load(input_file).get("CFBundleLocalizations", ()))
            )

    errors: list[str] = []
    incomplete: list[str] = []
    for label, path in CATALOGS:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        strings = catalog["strings"]
        locales = languages_by_target[0 if label.startswith("Recipe") else 1]
        source = catalog["sourceLanguage"]
        print(f"\\n{label}: {len(strings)} entries")
        for language in sorted(locales):
            if language == source:
                print(f"  {language}: source language (complete by key fallback)")
                continue
            missing = []
            for key, entry in strings.items():
                units = translated_units(entry.get("localizations", {}).get(language, {}))
                if not units:
                    missing.append(key)
                    continue
                expected = placeholders(key)
                for value in units:
                    if placeholders(value) != expected:
                        errors.append(
                            f"{path.name}: {language}: placeholders differ for {key!r}"
                        )
            coverage = len(strings) - len(missing)
            print(f"  {language}: {coverage}/{len(strings)} translated; {len(missing)} English fallbacks")
            if missing:
                incomplete.append(f"{label}: {language}: {len(missing)} missing")
        if catalog.get("sourceLanguage") != "en":
            errors.append(f"{path.name}: expected English as source language")

    for error in errors:
        print(f"ERROR: {error}")
    if strict:
        for finding in incomplete:
            print(f"INCOMPLETE: {finding}")
    return 1 if errors or (strict and incomplete) else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="Require 100% coverage")
    args = parser.parse_args()
    raise SystemExit(run(strict=args.strict))
