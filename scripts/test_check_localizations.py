#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Regress XLIFF placeholder signatures, literal percents and translation failures.

from __future__ import annotations

import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import check_localizations as audit


XLIFF_NS = "urn:oasis:names:tc:xliff:document:1.2"


class XLIFFPlaceholderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="xliff-placeholders-")
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_xliff(self, *entries: tuple[str, str | None, str]) -> None:
        xliff = self.root / "de.xcloc" / "Localized Contents" / "de.xliff"
        xliff.parent.mkdir(parents=True, exist_ok=True)
        root = ET.Element(f"{{{XLIFF_NS}}}xliff", {"version": "1.2"})
        file_element = ET.SubElement(root, f"{{{XLIFF_NS}}}file")
        body = ET.SubElement(file_element, f"{{{XLIFF_NS}}}body")
        for index, (source, target, state) in enumerate(entries, 1):
            unit = ET.SubElement(body, f"{{{XLIFF_NS}}}trans-unit", {"id": str(index)})
            ET.SubElement(unit, f"{{{XLIFF_NS}}}source").text = source
            if target is not None:
                ET.SubElement(unit, f"{{{XLIFF_NS}}}target", {"state": state}).text = target
        ET.ElementTree(root).write(xliff, encoding="utf-8", xml_declaration=True)

    def test_rejects_same_count_different_placeholder_types(self) -> None:
        self.write_xliff(("Hello %@", "Hallo %lld", "translated"))
        failures = audit.check_locale(self.root, "de")
        self.assertEqual(len(failures), 1)
        self.assertIn("placeholder signature changed", failures[0])
        self.assertIn("%@", failures[0])
        self.assertIn("lld", failures[0])

    def test_allows_explicit_positional_reorder(self) -> None:
        self.write_xliff((
            "Found %lld rows for %@",
            "Für %2$@ wurden %1$lld Zeilen gefunden",
            "translated",
        ))
        self.assertEqual(audit.check_locale(self.root, "de"), [])

    def test_rejects_implicit_reorder_with_incompatible_argument_positions(self) -> None:
        self.write_xliff(("Found %lld rows for %@", "Für %@ wurden %lld Zeilen gefunden", "translated"))
        self.assertEqual(len(audit.check_locale(self.root, "de")), 1)

    def test_rejects_repeated_wrong_positional_argument(self) -> None:
        self.write_xliff(("%@ and %@", "%1$@ und %1$@", "translated"))
        self.assertEqual(len(audit.check_locale(self.root, "de")), 1)

    def test_rejects_missing_or_duplicated_placeholders(self) -> None:
        self.write_xliff(
            ("Saved %@ of %lld", "Gespeichert %@", "translated"),
            ("Saved %@", "Gespeichert %@ %@", "translated"),
        )
        self.assertEqual(len(audit.check_locale(self.root, "de")), 2)

    def test_ignores_escaped_percent_and_checks_real_placeholder(self) -> None:
        self.assertEqual(audit.placeholders("100%%, %%@, %1$@"), [(1, "@")])
        self.write_xliff(("100%%, %@", "100%%, %1$@", "translated"))
        self.assertEqual(audit.check_locale(self.root, "de"), [])

    def test_recognizes_legacy_long_unsigned_and_float_precision(self) -> None:
        self.assertEqual(
            audit.placeholders("%llu / %lu / %u / %.2f / %g / %s"),
            [(1, "llu"), (2, "lu"), (3, "u"), (4, "f"), (5, "g"), (6, "s")],
        )
        self.write_xliff(("Received %llu", "Empfangen %lld", "translated"))
        self.assertEqual(len(audit.check_locale(self.root, "de")), 1)

    def test_missing_translation_and_placeholder_only_fallback(self) -> None:
        self.write_xliff(
            ("Welcome", None, ""),
            ("%@ — %llu", None, ""),
            ("Settings", "Einstellungen", "needs-review-translation"),
        )
        errors = audit.check_locale(self.root, "de")
        self.assertEqual(len(errors), 2)
        self.assertIn("Welcome", errors[0])
        self.assertIn("Settings", errors[1])

    def test_missing_export_and_empty_xliff_are_errors(self) -> None:
        self.assertIn("did not export", audit.check_locale(self.root, "de")[0])
        self.write_xliff()
        self.assertIn("no localization entries", audit.check_locale(self.root, "de")[0])

    def test_translated_normal_text_succeeds(self) -> None:
        self.write_xliff(("Welcome", "Willkommen", "translated"))
        self.assertEqual(audit.check_locale(self.root, "de"), [])


if __name__ == "__main__":
    unittest.main()
