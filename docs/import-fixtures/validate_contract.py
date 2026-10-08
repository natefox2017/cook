#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Validate versioned RecipePouch import contract fixtures and OpenAPI references.

"""Run from any working directory: python3 docs/import-fixtures/validate_contract.py."""

import json
import sys
import urllib.parse
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


def validate_openapi_references(
    api: dict, definitions: set[str]
) -> None:
    assert api["openapi"].startswith("3.1."), "OpenAPI 3.1 is required"
    assert "/recipe-imports" in api["paths"]
    assert "/recipe-imports/{job_id}" in api["paths"]
    assert "bearerAuth" in api["components"]["securitySchemes"]

    def inspect(value: object) -> None:
        if isinstance(value, dict):
            if "$ref" in value:
                reference = value["$ref"]
                external_prefix = "./import-v1.schema.json#/$defs/"
                if reference.startswith(external_prefix):
                    assert reference[len(external_prefix):] in definitions, (
                        f"Missing external schema definition: {reference}"
                    )
                elif reference.startswith("#/components/"):
                    target: object = api
                    for token in reference[2:].split("/"):
                        token = token.replace("~1", "/").replace("~0", "~")
                        if not isinstance(target, dict) or token not in target:
                            raise AssertionError(
                                f"Missing OpenAPI component reference: {reference}"
                            )
                        target = target[token]
                else:
                    raise AssertionError(f"Unexpected reference: {reference}")
            for child in value.values():
                inspect(child)
        elif isinstance(value, list):
            for child in value:
                inspect(child)

    inspect(api["paths"])


def has_well_formed_import_source(case: dict) -> bool:
    if case["schema"] != "ImportRequest":
        return True
    request = case["data"]
    input_type = request.get("input_type")
    if input_type == "text":
        text = request.get("text")
        if not isinstance(text, str) or not text.strip():
            return False
    raw_urls = []
    if input_type == "url":
        raw_urls.append(request.get("url"))
    if "original_source_url" in request:
        raw_urls.append(request.get("original_source_url"))

    for raw_url in raw_urls:
        if raw_url is None:
            continue
        try:
            parsed = urllib.parse.urlsplit(raw_url)
            port = parsed.port
        except (TypeError, ValueError):
            return False

        if not (
            parsed.scheme == "https"
            and bool(parsed.hostname)
            and parsed.username is None
            and parsed.password is None
            and port in (None, 443)
        ):
            return False
    return True


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
        observed_valid = not errors and has_well_formed_import_source(case)

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
