#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Validate versioned RecipePouch import contract fixtures and OpenAPI references.

"""Run from any working directory: python3 docs/import-fixtures/validate_contract.py."""

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError:
    sys.exit("Missing jsonschema: python3 -m pip install 'jsonschema>=4.21'")

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schemas" / "import-v1.schema.json"
OPENAPI_PATH = ROOT / "schemas" / "import-v1.openapi.json"
EXAMPLES_PATH = Path(__file__).with_name("contract-examples.json")


def read_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def validate_openapi_references(api: dict, definitions: set[str]) -> None:
    assert api["openapi"].startswith("3.1."), "OpenAPI 3.1 is required"
    assert "/recipe-imports" in api["paths"]
    assert "/recipe-imports/{job_id}" in api["paths"]
    assert "bearerAuth" in api["components"]["securitySchemes"]

    def inspect(value: object) -> None:
        if isinstance(value, dict):
            if "$ref" in value:
                reference = value["$ref"]
                prefix = "./import-v1.schema.json#/$defs/"
                assert reference.startswith(prefix), f"Unexpected reference: {reference}"
                assert reference[len(prefix):] in definitions, f"Missing definition: {reference}"
            for child in value.values():
                inspect(child)
        elif isinstance(value, list):
            for child in value:
                inspect(child)

    inspect(api["paths"])


def main() -> int:
    schema = read_json(SCHEMA_PATH)
    api = read_json(OPENAPI_PATH)
    fixtures = read_json(EXAMPLES_PATH)

    Draft202012Validator.check_schema(schema)
    definitions = schema["$defs"]
    validate_openapi_references(api, set(definitions))

    cases = fixtures["cases"]
    if not any(case["valid"] for case in cases):
        raise AssertionError("No positive fixtures")
    if not any(not case["valid"] for case in cases):
        raise AssertionError("No negative fixtures")

    failures: list[str] = []
    checker = FormatChecker()

    for case in cases:
        definition = case["schema"]
        if definition not in definitions:
            failures.append(f"{case['name']}: unknown schema {definition}")
            continue

        # Keep the referenced definitions in one shared validator. Using the
        # definition alone would break local #/$defs references.
        selected = {
            "$schema": schema["$schema"],
            "$defs": definitions,
            "$ref": f"#/$defs/{definition}",
        }
        validator = Draft202012Validator(selected, format_checker=checker)
        errors = list(validator.iter_errors(case["data"]))
        observed_valid = not errors

        if observed_valid != case["valid"]:
            details = "; ".join(error.message for error in errors[:2])
            failures.append(
                f"{case['name']}: expected valid={case['valid']}; "
                f"got valid={observed_valid}; {details}"
            )

    print(
        f"Validated {len(cases)} import fixtures "
        f"({sum(bool(case['valid']) for case in cases)} positive / "
        f"{sum(not case['valid'] for case in cases)} negative), "
        "plus OpenAPI external schema references."
    )

    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
