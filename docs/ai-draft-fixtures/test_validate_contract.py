# Developer: gengyun
# Purpose: Verify the DEV-291 static checker rejects broken refs, unsafe authority and inconsistent budgets.
import copy
import unittest
from validate_contract import definition_validator, load, validate_contract


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.api, self.schema, self.fixtures, self.document = copy.deepcopy(load())

    def check(self):
        return validate_contract(self.api, self.schema, self.fixtures, self.document)

    def test_baseline(self):
        self.assertGreater(self.check(), 20)

    def test_broken_reference(self):
        self.api["paths"]["/recipe-draft-sessions"]["post"]["requestBody"]["content"]["application/json"]["schema"]["$ref"] = "./recipe-draft-v1.schema.json#/$defs/missing"
        with self.assertRaises(ValueError):
            self.check()

    def test_removed_security(self):
        self.api["paths"]["/recipe-draft-sessions"]["post"]["security"] = []
        with self.assertRaises(ValueError):
            self.check()

    def test_budget_disagreement(self):
        self.schema["x-budget-policy"]["session_token_limit"] += 1
        with self.assertRaises(ValueError):
            self.check()

    def test_enabled_default(self):
        self.api["x-budget-policy"]["enabled_by_default"] = True
        with self.assertRaises(ValueError):
            self.check()

    def test_owner_authority_added_to_schema(self):
        self.schema["$defs"]["TurnRequest"]["properties"]["owner_id"] = {"type": "string"}
        with self.assertRaises(ValueError):
            self.check()

    def test_extra_request_properties_allowed(self):
        self.schema["$defs"]["ApprovalRequest"]["additionalProperties"] = True
        with self.assertRaises(ValueError):
            self.check()

    def test_wrong_success_status(self):
        operation = self.api["paths"]["/recipe-draft-sessions/{session_id}/turns"]["post"]
        operation["responses"]["201"] = operation["responses"].pop("202")
        with self.assertRaises(ValueError):
            self.check()

    def test_revision_bigint_bounds(self):
        validator = definition_validator(self.schema, "Revision")
        for valid in ("1", "999999999999999999", "9223372036854775807"):
            self.assertTrue(validator.is_valid(valid), valid)
        for invalid in ("0", "01", "9223372036854775808", "9999999999999999999", 1):
            self.assertFalse(validator.is_valid(invalid), invalid)

    def test_valid_fixture_corrupted(self):
        self.fixtures["cases"][0]["data"]["job_id"] = "bad-uuid"
        with self.assertRaises(ValueError):
            self.check()

    def test_combined_budget_overflow(self):
        case = next(case for case in self.fixtures["cases"] if case["schema"] == "Session")
        case["data"]["budget"] = {"reserved_tokens": 32768, "settled_tokens": 1, "dispatch_count": 0}
        with self.assertRaises(ValueError):
            self.check()

    def test_pending_cannot_publish_proposal(self):
        validator = definition_validator(self.schema, "Turn")
        pending = next(case["data"] for case in self.fixtures["cases"] if case["name"] == "pending")
        proposal = next(case["data"]["result"] for case in self.fixtures["cases"] if case["name"] == "proposal")
        pending["result"] = proposal
        self.assertFalse(validator.is_valid(pending))

    def test_terminal_cannot_be_202_pending_response(self):
        case = next(case for case in self.fixtures["cases"] if case["name"] == "proposal")
        case["operation"][2] = "202"
        with self.assertRaises(ValueError):
            self.check()

    def test_receipt_requires_selected_paths_for_accept(self):
        case = next(case for case in self.fixtures["cases"] if case["name"] == "receipt")
        case["data"]["selected_paths"] = []
        with self.assertRaises(ValueError):
            self.check()

    def test_deleted_unknown_recovery_disclosure(self):
        self.document = self.document.replace("**", "").replace("not automatically dispatched again", "automatically retried")
        with self.assertRaises(ValueError):
            self.check()


if __name__ == "__main__":
    unittest.main()
