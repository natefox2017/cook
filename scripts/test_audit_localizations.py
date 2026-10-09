# Developer: gengyun
# Purpose: Exercise String Catalog audit coverage, plural completion and placeholder safety.

import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import audit_localizations as audit


class LocalizationAuditTests(unittest.TestCase):
    def test_positional_placeholders_preserve_types_without_forcing_order(self):
        self.assertEqual(
            audit.placeholders("%lld rows and %@"),
            audit.placeholders("%2$@ and %1$lld"),
        )
        self.assertNotEqual(audit.placeholders("%lld"), audit.placeholders("%@"))
        self.assertEqual(audit.placeholders("100%% %@"), ["%@"])

    def test_plural_requires_every_declared_variant_to_be_translated(self):
        entry = {
            "variations": {
                "plural": {
                    "one": {"stringUnit": {"state": "translated", "value": "%lld item"}},
                    "other": {"stringUnit": {"state": "needs_review", "value": "%lld items"}},
                }
            }
        }
        self.assertEqual(audit.translated_units(entry), [])
        entry["variations"]["plural"]["other"]["stringUnit"]["state"] = "translated"
        self.assertEqual(audit.translated_units(entry), ["%lld item", "%lld items"])

    def test_strict_reports_missing_advertised_locale_but_skips_nonstranslatable_keys(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = root / "app.plist"
            extension = root / "extension.plist"
            app.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en", "de"]}))
            extension.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en", "de"]}))
            catalog = root / "strings.xcstrings"
            catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {
                    "Add recipe": {"localizations": {}},
                    "Internal identifier": {"shouldTranslate": False},
                },
            }), encoding="utf-8")
            with (
                patch.object(audit, "PLISTS", (app, extension)),
                patch.object(audit, "CATALOGS", (("Recipe", catalog),)),
            ):
                self.assertEqual(audit.run(strict=False), 0)
                self.assertEqual(audit.run(strict=True), 1)

    def test_strict_accepts_a_fully_translated_catalog(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            plist = root / "app.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en", "de"]}))
            catalog = root / "strings.xcstrings"
            catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {
                    "Hello %@": {
                        "localizations": {
                            "de": {"stringUnit": {"state": "translated", "value": "Hallo %@"}}
                        }
                    }
                },
            }), encoding="utf-8")
            with (
                patch.object(audit, "PLISTS", (plist, plist)),
                patch.object(audit, "CATALOGS", (("Recipe", catalog),)),
            ):
                self.assertEqual(audit.run(strict=True), 0)


if __name__ == "__main__":
    unittest.main()
