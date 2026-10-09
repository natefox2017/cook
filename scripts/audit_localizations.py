#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Audit the completeness and interpolation safety of shipped Xcode String Catalogs.

"""Report untranslated catalog entries; --strict requires all advertised locales."""

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
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|llu|ld|lu|d|u|@|s|f|g)")
POSITION = re.compile(r"^%\d+\$")


def placeholders(text: str) -> list[str]:
    """Match format type and multiplicity; allow reordered positional arguments."""
    return sorted(POSITION.sub("%", token) for token in PLACEHOLDER.findall(text.replace("%%", "")))


def translated_units(localization: dict) -> list[str]:
    """A plural localization is complete only when every declared branch is translated."""
    if "stringUnit" in localization:
        unit = localization["stringUnit"]
        return [unit["value"]] if unit.get("state") == "translated" and unit.get("value") else []

    variations = localization.get("variations", {})
    if not variations:
        return []
    values: list[str] = []
    for form, choices in variations.items():
        if not isinstance(choices, dict) or (form == "plural" and "other" not in choices):
            return []
        for choice in choices.values():
            unit = choice.get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value"):
                return []
            values.append(unit["value"])
    return values

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
        strings = {
            key: value
            for key, value in catalog["strings"].items()
            if value.get("shouldTranslate") is not False
        }
        locales = languages_by_target[0 if label.startswith("Recipe") else 1]
        source = catalog["sourceLanguage"]
        print(f"\n{label}: {len(strings)} translatable entries")
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

    for error in errors[:25]:
        print(f"ERROR: {error}")
    if len(errors) > 25:
        print(f"ERROR: {len(errors) - 25} further placeholder/source errors omitted")
    if strict:
        for finding in incomplete:
            print(f"INCOMPLETE: {finding}")
    return 1 if errors or (strict and incomplete) else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="Require 100% coverage")
    args = parser.parse_args()
    raise SystemExit(run(strict=args.strict))
