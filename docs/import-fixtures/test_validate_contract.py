#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Regression coverage for OpenAPI references beyond the paths section.

import copy
import unittest

from validate_contract import (
    OPENAPI_PATH,
    SCHEMA_PATH,
    read_json,
    validate_openapi_references,
)


class OpenAPIReferenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.api = read_json(OPENAPI_PATH)
        self.definitions = set(read_json(SCHEMA_PATH)["$defs"])

    def validate(self, api: dict) -> None:
        validate_openapi_references(api, self.definitions)

    def test_actual_contract_resolves_all_local_and_external_references(self) -> None:
        self.validate(self.api)

    def test_missing_component_reference_fails_even_outside_paths(self) -> None:
        broken = copy.deepcopy(self.api)
        broken["components"]["schemas"]["ArtifactResponse"]["properties"]["artifact"][
            "$ref"
        ] = "#/components/schemas/DoesNotExist"
        with self.assertRaisesRegex(AssertionError, "Missing local definition"):
            self.validate(broken)

    def test_missing_external_reference_fails_even_outside_paths(self) -> None:
        broken = copy.deepcopy(self.api)
        broken["components"]["schemas"]["ArtifactMetadata"][
            "$ref"
        ] = "./import-v1.schema.json#/$defs/DoesNotExist"
        with self.assertRaisesRegex(AssertionError, "Missing external definition"):
            self.validate(broken)

    def test_unrecognized_remote_reference_is_rejected(self) -> None:
        broken = copy.deepcopy(self.api)
        broken["components"]["schemas"]["ArtifactMetadata"][
            "$ref"
        ] = "https://untrusted.example/schema.json"
        with self.assertRaisesRegex(AssertionError, "Unexpected reference"):
            self.validate(broken)

    def test_non_string_reference_is_rejected(self) -> None:
        broken = copy.deepcopy(self.api)
        broken["components"]["schemas"]["ArtifactMetadata"]["$ref"] = None
        with self.assertRaisesRegex(AssertionError, "Non-string"):
            self.validate(broken)


if __name__ == "__main__":
    unittest.main()
