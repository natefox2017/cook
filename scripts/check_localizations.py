#!/usr/bin/env python3
"""Fail when Xcode-extracted user-facing strings lack a supported translation."""

from __future__ import annotations

import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path


REQUIRED_LOCALES = ("ja", "zh-Hans", "zh-Hant")
XLIFF_NAMESPACE = {"xliff": "urn:oasis:names:tc:xliff:document:1.2"}
PLACEHOLDER = re.compile(
    r"%(?:(?P<position>[1-9]\d*)\$)?[-+ #0]*\d*(?:\.\d+)?"
    r"(?P<kind>lld|llu|ld|lu|d|u|@|s|f|g)"
)


def placeholders(value: str) -> list[tuple[int, str]]:
    """Pair each format argument position with its type; ignore escaped percents."""
    return sorted(
        (int(match.group("position") or index), match.group("kind"))
        for index, match in enumerate(PLACEHOLDER.finditer(value.replace("%%", "")), 1)
    )


def is_placeholder_only(value: str) -> bool:
    remainder = PLACEHOLDER.sub("", value.replace("%%", ""))
    return not any(
        not character.isspace() and not unicodedata.category(character).startswith("P")
        for character in remainder
    )


def text_content(element: ET.Element | None) -> str:
    if element is None:
        return ""
    return "".join(element.itertext()).strip()


def check_locale(export_root: Path, locale: str) -> list[str]:
    xliff = export_root / f"{locale}.xcloc" / "Localized Contents" / f"{locale}.xliff"
    if not xliff.is_file():
        return [f"{locale}: Xcode did not export a localization file at {xliff}"]

    errors: list[str] = []
    root = ET.parse(xliff).getroot()
    units = root.findall(".//xliff:trans-unit", XLIFF_NAMESPACE)
    if not units:
        return [f"{locale}: Xcode exported no localization entries"]

    for unit in units:
        source = text_content(unit.find("xliff:source", XLIFF_NAMESPACE))
        target_element = unit.find("xliff:target", XLIFF_NAMESPACE)
        target = text_content(target_element)
        state = target_element.get("state", "") if target_element is not None else ""
        if not target or state in {"new", "needs-translation", "needs-review-translation"}:
            # A value made only of a substitution and punctuation has no language to translate.
            if is_placeholder_only(source):
                continue
            errors.append(f"{locale}: missing translation for {source!r}")
            continue

        source_placeholders = placeholders(source)
        target_placeholders = placeholders(target)
        if source_placeholders != target_placeholders:
            errors.append(
                f"{locale}: placeholder signature changed for {source!r}: "
                f"expected {source_placeholders}, found {target_placeholders}"
            )

    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check_localizations.py <xcode-localization-export>", file=sys.stderr)
        return 2

    export_root = Path(sys.argv[1])
    errors = [
        error
        for locale in REQUIRED_LOCALES
        for error in check_locale(export_root, locale)
    ]
    if errors:
        print("Localization check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Validated Xcode-extracted translations for: {', '.join(REQUIRED_LOCALES)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
