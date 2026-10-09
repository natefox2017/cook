#!/usr/bin/env python3
"""Regression fixtures for the app and Share Extension display-name guard."""

from __future__ import annotations

import json
import plistlib
import tempfile
import unittest
from pathlib import Path

from scripts.check_ios_branding import BUNDLES, NAMES, validate


class IOSBrandingValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="recipe-branding-")
        self.root = Path(self.temporary.name)
        for plist_name, catalog_name in BUNDLES:
            plist_path = self.root / plist_name
            plist_path.parent.mkdir(parents=True, exist_ok=True)
            with plist_path.open("wb") as file:
                plistlib.dump(
                    {"CFBundleName": NAMES["en"], "CFBundleDisplayName": NAMES["en"]},
                    file,
                )

            catalog_path = self.root / catalog_name
            catalog_path.parent.mkdir(parents=True, exist_ok=True)
            self.write_catalog(
                catalog_path,
                {
                    "strings": {
                        key: {
                            "localizations": {
                                locale: {
                                    "stringUnit": {
                                        "state": "translated",
                                        "value": name,
                                    }
                                }
                                for locale, name in NAMES.items()
                            }
                        }
                        for key in ("CFBundleName", "CFBundleDisplayName")
                    }
                },
            )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def write_catalog(path: Path, value: dict) -> None:
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")

    def test_all_four_localized_names_are_accepted_for_both_targets(self) -> None:
        self.assertEqual(validate(self.root), [])

    def test_legacy_or_mismatched_bundle_names_are_rejected(self) -> None:
        for plist_name, _ in BUNDLES:
            for key in ("CFBundleName", "CFBundleDisplayName"):
                with self.subTest(target=plist_name, key=key):
                    path = self.root / plist_name
                    with path.open("rb") as file:
                        original = plistlib.load(file)
                    changed = dict(original, **{key: "RecipePouch"})
                    with path.open("wb") as file:
                        plistlib.dump(changed, file)
                    self.assertTrue(
                        any(f"{plist_name}: {key}" in error for error in validate(self.root))
                    )
                    with path.open("wb") as file:
                        plistlib.dump(original, file)

    def test_every_catalog_locale_and_key_is_checked_in_both_targets(self) -> None:
        for _, catalog_name in BUNDLES:
            for key in ("CFBundleName", "CFBundleDisplayName"):
                for locale in NAMES:
                    with self.subTest(target=catalog_name, key=key, locale=locale):
                        path = self.root / catalog_name
                        original = json.loads(path.read_text(encoding="utf-8"))
                        changed = json.loads(json.dumps(original))
                        changed["strings"][key]["localizations"][locale]["stringUnit"][
                            "value"
                        ] = "RecipePouch"
                        self.write_catalog(path, changed)
                        self.assertTrue(
                            any(
                                f"{catalog_name}: {key}[{locale}]" in error
                                for error in validate(self.root)
                            )
                        )
                        self.write_catalog(path, original)

    def test_missing_translation_fails_closed(self) -> None:
        _, catalog_name = BUNDLES[1]
        path = self.root / catalog_name
        data = json.loads(path.read_text(encoding="utf-8"))
        del data["strings"]["CFBundleDisplayName"]["localizations"]["zh-Hans"]
        self.write_catalog(path, data)
        self.assertTrue(
            any("CFBundleDisplayName[zh-Hans]" in error for error in validate(self.root))
        )


if __name__ == "__main__":
    unittest.main()
