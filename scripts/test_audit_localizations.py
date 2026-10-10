# Developer: gengyun
# Purpose: Exercise String Catalog audit coverage, plural completion and placeholder safety.

import argparse
import io
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
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

    def test_positional_arguments_bind_types_to_original_argument_indexes(self):
        source = "%lld rows and %@"
        self.assertEqual(
            audit.placeholder_arguments(source),
            audit.placeholder_arguments("%2$@ and %1$lld"),
        )
        for invalid in (
            "%1$@ and %2$lld",
            "%@ and %lld",
            "%1$@ and %lld",
            "%0$lld and %2$@",
        ):
            with self.subTest(invalid=invalid):
                self.assertNotEqual(
                    audit.placeholder_arguments(source),
                    audit.placeholder_arguments(invalid),
                )
        self.assertIsNone(audit.placeholder_arguments("%1$@ and %lld"))
        self.assertIsNone(audit.placeholder_arguments("%0$@"))
        self.assertEqual(audit.placeholder_arguments("100%% complete: %@"), [(1, "%@")])
        self.assertNotEqual(
            audit.placeholder_arguments("%@ %@"),
            audit.placeholder_arguments("%1$@ %1$@"),
        )

    def test_non_strict_audit_rejects_wrong_positional_types(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            plist = root / "app.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en", "de"]}))
            catalog = root / "strings.xcstrings"
            source = "%lld rows and %@"
            contents = {
                "sourceLanguage": "en",
                "strings": {
                    source: {
                        "localizations": {
                            "de": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "%1$@ und %2$lld",
                                }
                            }
                        }
                    }
                },
            }
            catalog.write_text(json.dumps(contents), encoding="utf-8")
            with (
                patch.object(audit, "PLISTS", (plist, plist)),
                patch.object(audit, "CATALOGS", (("Recipe", catalog),)),
                redirect_stdout(io.StringIO()) as output,
            ):
                self.assertEqual(audit.run(strict=False), 1)
                self.assertEqual(audit.run(strict=True), 1)
                contents["strings"][source]["localizations"]["de"]["stringUnit"]["value"] = (
                    "%2$@ und %1$lld"
                )
                catalog.write_text(json.dumps(contents), encoding="utf-8")
                self.assertEqual(audit.run(strict=True), 0)
            self.assertIn("de: placeholders differ", output.getvalue())
            self.assertIn(repr(source), output.getvalue())

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

    def test_extension_inherits_app_locales_when_plist_omits_languages(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = root / "app.plist"
            extension = root / "extension.plist"
            app.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en", "de"]}))
            extension.write_bytes(plistlib.dumps({"CFBundleDisplayName": "Recipe Pals"}))
            catalog = root / "strings.xcstrings"
            catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {"Share recipe": {"localizations": {}}},
            }), encoding="utf-8")
            with (
                patch.object(audit, "PLISTS", (app, extension)),
                patch.object(audit, "CATALOGS", (("Share Extension", catalog),)),
            ):
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


    def test_optional_locale_reports_unshipped_extension_gap_without_changing_default(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = root / "app.plist"
            extension = root / "extension.plist"
            app.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en"]}))
            extension.write_bytes(plistlib.dumps({"CFBundleDisplayName": "Recipe Pals"}))
            app_catalog = root / "app.xcstrings"
            share_catalog = root / "share.xcstrings"
            app_catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {
                    "Hello": {"localizations": {
                        "de": {"stringUnit": {"state": "translated", "value": "Hallo"}}
                    }}
                }
            }), encoding="utf-8")
            share_catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {"Share": {"localizations": {}}},
            }), encoding="utf-8")

            with (
                patch.object(audit, "PLISTS", (app, extension)),
                patch.object(audit, "CATALOGS", (
                    ("Recipe", app_catalog), ("Share Extension", share_catalog),
                )),
                redirect_stdout(io.StringIO()) as output,
            ):
                self.assertEqual(audit.run(strict=True), 0)
                self.assertEqual(audit.run(strict=False, languages=("de",)), 0)
                self.assertEqual(audit.run(strict=True, languages=("de",)), 1)
                self.assertEqual(audit.run(strict=True, languages=("de", "de")), 1)
            log = output.getvalue()
            self.assertIn("de: 1/1 translated", log)
            self.assertIn("de: 0/1 translated", log)
            self.assertIn("INCOMPLETE: Share Extension: de: 1 missing", log)

    def test_multiple_unshipped_languages_still_fail_bad_placeholder_types(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            plist = root / "app.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en"]}))
            catalog = root / "strings.xcstrings"
            catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {"Hello %@": {"localizations": {
                    "de": {"stringUnit": {"state": "translated", "value": "Hallo %@"}},
                    "fr": {"stringUnit": {"state": "translated", "value": "Bonjour %lld"}},
                }}},
            }), encoding="utf-8")
            with (
                patch.object(audit, "PLISTS", (plist, plist)),
                patch.object(audit, "CATALOGS", (("Recipe", catalog),)),
                redirect_stdout(io.StringIO()) as output,
            ):
                self.assertEqual(audit.run(strict=True, languages=("de",)), 0)
                self.assertEqual(audit.run(strict=False, languages=("de", "fr")), 1)
                self.assertEqual(audit.run(strict=True, languages=("de", "de")), 0)
            log = output.getvalue()
            self.assertIn("placeholders differ for 'Hello %@'", log)

    def test_explicit_brazilian_portuguese_never_borrows_generic_pt(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            plist = root / "app.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en"]}))
            catalog = root / "strings.xcstrings"
            catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {"Cook": {"localizations": {
                    "pt": {"stringUnit": {"state": "translated", "value": "Cozinhar"}}
                }}},
            }), encoding="utf-8")
            with (
                patch.object(audit, "PLISTS", (plist, plist)),
                patch.object(audit, "CATALOGS", (("Recipe", catalog),)),
                redirect_stdout(io.StringIO()) as output,
            ):
                self.assertEqual(audit.run(strict=True, languages=("pt-BR",)), 1)
                self.assertEqual(audit.run(strict=True, languages=("pt",)), 0)
            log = output.getvalue()
            self.assertIn("pt-BR: 0/1 translated; 1 English fallbacks", log)

    def test_help_output_supports_literal_percent_and_new_locale_argument(self):
        result = subprocess.run(
            [sys.executable, str(Path(audit.__file__)), "--help"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("100% coverage", result.stdout)
        self.assertIn("--language CODE", result.stdout)

    def test_cli_accepts_bcp47_language_tags_not_paths_or_injection(self):
        for valid in ["en", "de", "pt-BR", "zh-Hans", "en-US"]:
            self.assertEqual(audit.locale_code(valid), valid)
        for invalid in ["", "en_US", "pt-", "../private", "https://example.com/de"]:
            with self.assertRaises(argparse.ArgumentTypeError):
                audit.locale_code(invalid)

    def test_explicit_source_english_still_uses_normal_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            plist = root / "app.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleLocalizations": ["en"]}))
            catalog = root / "strings.xcstrings"
            catalog.write_text(json.dumps({
                "sourceLanguage": "en",
                "strings": {"Welcome": {"localizations": {}}},
            }), encoding="utf-8")
            with (
                patch.object(audit, "PLISTS", (plist, plist)),
                patch.object(audit, "CATALOGS", (("Recipe", catalog),)),
                redirect_stdout(io.StringIO()) as output,
            ):
                self.assertEqual(audit.run(strict=True, languages=("en",)), 0)
            self.assertIn("en: source language", output.getvalue())


if __name__ == "__main__":
    unittest.main()
