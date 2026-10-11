#!/usr/bin/env python3
# Developer: gengyun
# Purpose: Validate the static DEV-291 draft schemas, OpenAPI references and synthetic fixtures offline.
"""Reuse the installed JSON Schema validator; this is not runtime API/DB verification."""
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parent.parent
POLICY = {
    "enabled_by_default": False,
    "tokens_per_dispatch": 4096,
    "session_dispatch_limit": 8,
    "session_token_limit": 32768,
    "owner_utc_day_token_limit": 65536,
    "lease_seconds": 30,
    "outer_deadline_ms": 10000,
}
OPERATIONS = {
    ("/recipe-draft-sessions", "post"): ("CreateSessionRequest", {"200": "Session", "201": "Session"}),
    ("/recipe-draft-sessions/{session_id}", "get"): (None, {"200": "Session"}),
    ("/recipe-draft-sessions/{session_id}/turns", "post"): ("TurnRequest", {"200": "TerminalTurn", "202": "PendingTurn"}),
    ("/recipe-draft-sessions/{session_id}/turns/{request_id}", "get"): (None, {"200": "Turn"}),
    ("/recipe-draft-sessions/{session_id}/turns/{request_id}/approval", "post"): ("ApprovalRequest", {"200": "ApprovalReceipt"}),
}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def load():
    return (
        read_json(ROOT / "schemas/recipe-draft-v1.openapi.json"),
        read_json(ROOT / "schemas/recipe-draft-v1.schema.json"),
        read_json(ROOT / "ai-draft-fixtures/contract-examples.json"),
        (ROOT / "AI/RECIPE_DRAFT_API_V1.md").read_text(encoding="utf-8"),
    )


def require(condition, message):
    if not condition:
        raise ValueError(message)


def pointer(document, reference):
    require(reference.startswith("#/"), f"Unexpected local reference: {reference}")
    target = document
    for token in reference[2:].split("/"):
        key = token.replace("~1", "/").replace("~0", "~")
        require(isinstance(target, dict) and key in target, f"Missing reference: {reference}")
        target = target[key]
    return target


def inspect_refs(value, document, schema):
    if isinstance(value, dict):
        if "$ref" in value:
            reference = value["$ref"]
            require(isinstance(reference, str), "Reference must be text")
            if reference.startswith("./recipe-draft-v1.schema.json#/"):
                pointer(schema, reference[len("./recipe-draft-v1.schema.json"):])
            else:
                pointer(document, reference)
        for child in value.values():
            inspect_refs(child, document, schema)
    elif isinstance(value, list):
        for child in value:
            inspect_refs(child, document, schema)


def definition_validator(schema, name):
    require(name in schema["$defs"], f"Unknown fixture schema: {name}")
    return Draft202012Validator(
        {"$ref": f"#/$defs/{name}", "$defs": schema["$defs"]},
        format_checker=FormatChecker(),
    )


def check_semantics(name, data):
    # JSON Schema handles shapes/formats. These are additional aggregate invariants.
    if isinstance(data, (dict, list)):
        encoded = json.dumps(data, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
        require(len(encoded) <= 32768, "Fixture JSON exceeds wire budget")
    if name == "Budget":
        require(data["reserved_tokens"] + data["settled_tokens"] <= 32768, "Combined session budget exceeded")
    if name == "Session":
        check_semantics("Budget", data["budget"])
        check_semantics("Context", data["context"])
        for path, overlay in data["overlay"].items():
            require(path in data["context"]["fields"], "Overlay missing from effective context")
            field = data["context"]["fields"][path]
            require(field["user_confirmed"] and field["raw_value"] == overlay["raw_value"]
                    and field["evidence_ids"] == overlay["evidence_ids"] and field["origin"] == "AI_suggested",
                    "Confirmed overlay and effective context disagree")
            require(int(overlay["confirmed_revision"]) <= int(data["revision"]), "Future overlay revision")
    if name == "Context":
        evidence = data["evidence"]
        require(len({item["id"] for item in evidence}) == len(evidence), "Duplicate evidence identity")
        require(sum(len(item["excerpt"]) for item in evidence) <= 20000, "Aggregate excerpt budget exceeded")
        ids = {item["id"] for item in evidence}
        require(all(set(field["evidence_ids"]) <= ids for field in data["fields"].values()), "Unknown field evidence")
    if name == "GenerationResult" and data["status"] == "proposal":
        for key in ("questions", "suggestions"):
            require(len({item["path"] for item in data[key]}) == len(data[key]), "Duplicate proposal path")
    if name == "Turn" and data["result"] is not None:
        check_semantics("GenerationResult", data["result"])
        if data["decision"] is not None:
            require(data["result"]["status"] == "proposal", "Only proposals can have decisions")
            require(data["decision"]["session_id"] == data["session_id"]
                    and data["decision"]["turn_request_id"] == data["request_id"], "Decision lineage mismatch")
            require(int(data["decision"]["applied_revision"]) > int(data["based_revision"]), "Decision must advance revision")


def validate_contract(api, schema, fixtures, document):
    Draft202012Validator.check_schema(schema)
    document = document.replace("**", "")
    require(api["openapi"].startswith("3.1."), "OpenAPI 3.1 required")
    require(api.get("x-budget-policy") == POLICY and schema.get("x-budget-policy") == POLICY,
            "Budget policy/default-disabled disagreement")
    require("not implemented or deployed" in document and "default-disabled" in document,
            "Specification must disclose deployment status")
    require("dispatched_unknown" in document and "not automatically dispatched again" in document,
            "Unknown dispatch recovery boundary missing")
    require("owner-day budget" in document and "must not refund" in document,
            "Deletion must not reset owner quota")
    require("JCS" in document and "UTF-16" in document and "SHA-256" in document,
            "Canonical hashing contract missing")
    require("9223372036854775807" in document, "Bigint wire bound missing")
    inspect_refs(api, api, schema)
    inspect_refs(schema, schema, schema)
    operations = {(path, method) for path, methods in api["paths"].items() for method in methods}
    require(operations == set(OPERATIONS), "Unexpected/missing draft operations")
    require(api["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer", "Bearer scheme required")
    operation_ids = set()
    for (path, method), (body, successes) in OPERATIONS.items():
        operation = api["paths"][path][method]
        require(operation.get("security") == [{"bearerAuth": []}], "Every operation requires owner JWT")
        require(operation["operationId"] not in operation_ids, "Duplicate operationId")
        operation_ids.add(operation["operationId"])
        parameters = {parameter["name"]: parameter for parameter in operation.get("parameters", [])}
        for name in ("session_id", "request_id"):
            if "{" + name + "}" in path:
                require(name in parameters and parameters[name]["required"] is True
                        and parameters[name]["in"] == "path", "Required UUID path parameter missing")
        if body:
            require(operation["requestBody"]["required"] is True, "Required body missing")
            require(operation["requestBody"]["content"]["application/json"]["schema"] == {
                "$ref": f"./recipe-draft-v1.schema.json#/$defs/{body}"}, "Request schema mismatch")
            definition = schema["$defs"][body]
            require(definition["additionalProperties"] is False, "Request extras must be forbidden")
            require(not {"owner_id", "evidence", "provider", "model", "secret", "raw_value"} & set(definition["properties"]),
                    "Client authority override forbidden")
        actual_successes = {code: value for code, value in operation["responses"].items() if code.startswith("2")}
        require(set(actual_successes) == set(successes), "Durable success status mismatch")
        for code, name in successes.items():
            require(actual_successes[code]["content"]["application/json"]["schema"] == {
                "$ref": f"./recipe-draft-v1.schema.json#/$defs/{name}"}, "Response schema mismatch")
        for code, response in operation["responses"].items():
            if not code.startswith("2"):
                require(response["content"]["application/json"]["schema"] == {
                    "$ref": "./recipe-draft-v1.schema.json#/$defs/APIError"}, "Error envelope mismatch")
        required_errors = {"401", "404", "500"} if method == "get" else {"401", "404", "409", "413", "422", "429", "503", "500"}
        require(required_errors <= set(operation["responses"]), "Required error status missing")
    valid_names = set()
    response_operations = set()
    for case in fixtures["cases"]:
        validator = definition_validator(schema, case["schema"])
        valid = validator.is_valid(case["data"])
        if valid:
            try:
                check_semantics(case["schema"], case["data"])
            except (ValueError, UnicodeError):
                valid = False
        require(valid == case["valid"], f"Unexpected fixture outcome: {case['name']}")
        if case["valid"]:
            valid_names.add(case["schema"])
            if "operation" in case:
                path, method, status = case["operation"]
                require((path, method) in OPERATIONS, "Unknown fixture operation")
                name = OPERATIONS[(path, method)][1][status]
                require(definition_validator(schema, name).is_valid(case["data"]), "Response fixture violates operation/status schema")
                response_operations.add((path, method))
    require({"CreateSessionRequest", "TurnRequest", "ApprovalRequest", "Session", "Turn", "ApprovalReceipt", "APIError"} <= valid_names,
            "Operation fixture coverage missing")
    require(response_operations == set(OPERATIONS), "Response operation coverage missing")
    return len(fixtures["cases"])


def main():
    count = validate_contract(*load())
    print(f"PASS: {count} static draft fixtures, JSON Schema and five authenticated OpenAPI operations.")
    print("Runtime JWT/RLS/CAS/provider/network/billing/native/staging/production NOT VERIFIED.")


if __name__ == "__main__":
    main()
