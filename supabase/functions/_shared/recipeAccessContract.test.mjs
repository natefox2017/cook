// Developer: Recipe Pals
// Purpose: Deterministic commercial access/usage wire validation and unsafe-input regression (DEV-425).

import test from "node:test";
import assert from "node:assert/strict";
import {
  accessResponse,
  reservationRequest,
  reservation,
  commitRequest,
  commitResponse,
  finalizeRequest,
  finalizeResponse,
  ackResponse,
  usageError,
  quota,
  isUUID,
  isHash,
  ERROR_STATUSES,
  POLICY,
  SAFE_INTEGER_MAX,
} from "./recipeAccessContract.mjs";

const owner = "a0000000-0000-4000-8000-000000000001";
const operation = "b0000000-0000-4000-8000-000000000002";
const recipe = "c0000000-0000-4000-8000-000000000003";
const requestID = "d0000000-0000-4000-8000-000000000004";
const job = "e0000000-0000-4000-8000-000000000005";
const candidateA = "candidate-v2-0123456789abcdef0123456789abcdef";
const candidateB = "candidate-v2-feedfacefeedfacefeedfacefeedface";
const candidateC = "candidate-0-a1b2c3d4e5f6a7b8";
const sessionID = "f0000000-0000-4000-8000-000000000004";
const turnRequestID = "f0000000-0000-4000-8000-000000000005";
const inputHash = "a".repeat(64);
const payloadHash = "b".repeat(64);

const freeAccess = {
  owner_id: owner,
  server_time: "2026-10-15T12:00:00.000Z",
  policy_version: 1,
  stage: "freeTest",
  entitlement: { status: "free", valid_until: null },
  capabilities: [
    { id: "smart_import", entitled: true, quota: { units: "successful_imports", period_type: "iso_week", period_start: "2026-10-12T00:00:00.000Z", reset_at: "2026-10-19T00:00:00.000Z", limit: 5, used: 2, reserved: 1, remaining: 2 } },
    { id: "ai_edit", entitled: true, quota: { units: "successful_edits", period_type: "lifetime", period_start: null, reset_at: null, limit: 3, used: 1, reserved: 0, remaining: 2 } },
    { id: "hands_free_cooking", entitled: false, quota: null },
    { id: "weekly_templates", entitled: false, quota: null },
    { id: "weekly_groceries", entitled: false, quota: null },
    { id: "auto_plan", entitled: false, quota: null },
    { id: "recipe_question", entitled: false, quota: null },
    { id: "recipe_translation", entitled: false, quota: null },
    { id: "media_import", entitled: false, quota: null },
    { id: "pdf_export", entitled: false, quota: null },
  ],
};

test("free access response normalizes all ten fixed capabilities", () => {
  const parsed = accessResponse(freeAccess);
  assert.ok(parsed, "free access response must validate");
  assert.equal(parsed.stage, "freeTest");
  assert.equal(parsed.owner_id, owner);
  assert.equal(parsed.capabilities.length, 10);
  const imports = parsed.capabilities.find((c) => c.id === "smart_import");
  assert.equal(imports.quota.remaining, 2);
  assert.equal(imports.quota.period_type, "iso_week");
});

test("premium access response grants monthly import and edit quotas", () => {
  const premium = {
    owner_id: owner,
    server_time: "2026-10-15T12:00:00.000Z",
    policy_version: 1,
    stage: "commercial",
    entitlement: { status: "premium", valid_until: "2026-11-01T00:00:00.000Z" },
    capabilities: [
      { id: "smart_import", entitled: true, quota: { units: "successful_imports", period_type: "utc_month", period_start: "2026-10-01T00:00:00.000Z", reset_at: "2026-11-01T00:00:00.000Z", limit: 100, used: 99, reserved: 0, remaining: 1 } },
      { id: "ai_edit", entitled: true, quota: { units: "successful_edits", period_type: "utc_month", period_start: "2026-10-01T00:00:00.000Z", reset_at: "2026-11-01T00:00:00.000Z", limit: 30, used: 5, reserved: 1, remaining: 24 } },
      { id: "hands_free_cooking", entitled: true, quota: null },
      { id: "weekly_templates", entitled: true, quota: null },
      { id: "weekly_groceries", entitled: true, quota: null },
      { id: "auto_plan", entitled: true, quota: null },
      { id: "recipe_question", entitled: true, quota: { units: "successful_answers", period_type: "utc_month", period_start: "2026-10-01T00:00:00.000Z", reset_at: "2026-11-01T00:00:00.000Z", limit: 100, used: 0, reserved: 0, remaining: 100 } },
      { id: "recipe_translation", entitled: true, quota: { units: "successful_translations", period_type: "utc_month", period_start: "2026-10-01T00:00:00.000Z", reset_at: "2026-11-01T00:00:00.000Z", limit: 20, used: 0, reserved: 0, remaining: 20 } },
      { id: "media_import", entitled: true, quota: { units: "media_tasks", period_type: "utc_month", period_start: "2026-10-01T00:00:00.000Z", reset_at: "2026-11-01T00:00:00.000Z", limit: 20, used: 0, reserved: 0, remaining: 20 } },
      { id: "pdf_export", entitled: true, quota: null },
    ],
  };
  const parsed = accessResponse(premium);
  assert.ok(parsed);
  assert.equal(parsed.entitlement.status, "premium");
  assert.equal(parsed.capabilities.length, 10);
  const edits = parsed.capabilities.find((c) => c.id === "ai_edit");
  assert.equal(edits.quota.limit, 30);
  assert.equal(edits.quota.period_type, "utc_month");
});

test("single-candidate reservation and settlement decode", () => {
  const request = reservationRequest({
    operation_id: operation, capability: "smart_import", input_hash: inputHash, estimated_units: 1,
    source: {
      origin: "import_job", job_id: job,
      candidate_ids: [candidateA],
      session_id: null, turn_request_id: null,
    },
  });
  assert.ok(request);
  assert.equal(request.estimated_units, 1);
  assert.equal(request.source.candidate_ids.length, 1);

  const held = reservation({
    operation_id: operation, owner_id: owner, capability: "smart_import",
    period_start: "2026-10-12T00:00:00.000Z", policy_version: 1,
    tier_at_reserve: "free", reserved_units: 1, status: "reserved",
    reserved_until: "2026-10-15T12:10:00.000Z",
  });
  assert.ok(held);
  assert.equal(held.tier_at_reserve, "free");

  const committed = commitResponse({
    operation_id: operation, status: "committed", committed_units: 1,
    period_start: "2026-10-12T00:00:00.000Z",
  });
  assert.ok(committed);

  const finalized = finalizeResponse({
    operation_id: operation, status: "finalized", recipe_id: recipe, payload_hash: payloadHash,
    committed_units: 1, period_start: "2026-10-12T00:00:00.000Z",
  });
  assert.ok(finalized);
  assert.equal(finalized.recipe_id, recipe);

  const ack = ackResponse({ operation_id: operation, status: "acked" });
  assert.ok(ack);
});

test("unknown capability is rejected", () => {
  const bad = structuredClone(freeAccess);
  bad.capabilities[0].id = "not_a_capability";
  assert.equal(accessResponse(bad), null);
});

test("negative quota count is rejected", () => {
  const bad = structuredClone(freeAccess);
  bad.capabilities[0].quota.used = -1;
  assert.equal(accessResponse(bad), null);
});

test("inconsistent remaining is rejected", () => {
  const bad = structuredClone(freeAccess);
  bad.capabilities[0].quota.remaining = 99;
  assert.equal(accessResponse(bad), null);
});

test("invalid period ordering is rejected", () => {
  const bad = structuredClone(freeAccess);
  bad.capabilities[0].quota.period_start = "2026-10-19T00:00:00.000Z";
  bad.capabilities[0].quota.reset_at = "2026-10-12T00:00:00.000Z";
  assert.equal(accessResponse(bad), null);
});

test("lifetime quota with period bounds is rejected", () => {
  const bad = structuredClone(freeAccess);
  bad.capabilities[1].quota.period_start = "2026-10-12T00:00:00.000Z";
  assert.equal(accessResponse(bad), null);
});

test("extra wire key is rejected", () => {
  const bad = structuredClone(freeAccess);
  bad.unexpected = "x";
  assert.equal(accessResponse(bad), null);
});

test("quota and upgrade errors map to their HTTP statuses", () => {
  const quotaError = usageError({
    code: "QUOTA_EXCEEDED", message: "Weekly import quota reached.", recoverable: true, request_id: requestID,
  });
  assert.ok(quotaError);
  assert.equal(ERROR_STATUSES.QUOTA_EXCEEDED, 402);
  const upgrade = usageError({
    code: "UPGRADE_REQUIRED", message: "Premium required.", recoverable: true, request_id: requestID,
  });
  assert.ok(upgrade);
  assert.equal(ERROR_STATUSES.UPGRADE_REQUIRED, 402);
});

test("unknown error code is rejected", () => {
  assert.equal(usageError({ code: "MADE_UP", message: "nope", recoverable: false, request_id: requestID }), null);
});

test("downgraded quota where used exceeds limit is accepted", () => {
  const q = quota({
    units: "successful_imports", period_type: "iso_week",
    period_start: "2026-10-12T00:00:00.000Z", reset_at: "2026-10-19T00:00:00.000Z",
    limit: 5, used: 7, reserved: 0, remaining: 0,
  });
  assert.ok(q);
  assert.equal(q.remaining, 0);
});

test("capability array containing null is rejected without throwing", () => {
  const bad = structuredClone(freeAccess);
  bad.capabilities = [null];
  assert.equal(accessResponse(bad), null);
});

test("count beyond the safe integer range is rejected", () => {
  const tooBig = SAFE_INTEGER_MAX + 1;
  assert.equal(quota({
    units: "successful_imports", period_type: "iso_week",
    period_start: "2026-10-12T00:00:00.000Z", reset_at: "2026-10-19T00:00:00.000Z",
    limit: tooBig, used: 0, reserved: 0, remaining: tooBig,
  }), null);
});

test("validators do not mutate their input", () => {
  const before = structuredClone(freeAccess);
  const snapshot = JSON.stringify(freeAccess);
  accessResponse(freeAccess);
  assert.equal(JSON.stringify(freeAccess), snapshot);
  assert.deepEqual(freeAccess, before);
});

test("uppercase UUIDs and hashes are rejected consistently", () => {
  assert.equal(isUUID(owner.toUpperCase()), false);
  assert.equal(isHash(inputHash.toUpperCase()), false);
  const bad = structuredClone(freeAccess);
  bad.owner_id = owner.toUpperCase();
  assert.equal(accessResponse(bad), null);
});

test("draft approval source and ai_edit finalize decode", () => {
  const request = finalizeRequest({
    capability: "ai_edit", input_hash: inputHash,
    source: { origin: "draft_approval", job_id: null, candidate_ids: null, session_id: sessionID, turn_request_id: turnRequestID },
  });
  assert.ok(request);
  assert.equal(request.source.origin, "draft_approval");
  assert.equal(request.source.session_id, sessionID);
});

test("import reservation with non-unit estimate is rejected", () => {
  assert.equal(reservationRequest({
    operation_id: operation, capability: "smart_import", input_hash: inputHash, estimated_units: 2,
    source: { origin: "import_job", job_id: job, candidate_ids: [candidateA], session_id: null, turn_request_id: null },
  }), null);
});

test("source capability mismatch is rejected", () => {
  assert.equal(reservationRequest({
    operation_id: operation, capability: "smart_import", input_hash: inputHash, estimated_units: 1,
    source: { origin: "draft_approval", job_id: null, candidate_ids: null, session_id: sessionID, turn_request_id: turnRequestID },
  }), null);
});

test("legacy opaque candidate id is accepted", () => {
  const request = reservationRequest({
    operation_id: operation, capability: "smart_import", input_hash: inputHash, estimated_units: 1,
    source: { origin: "import_job", job_id: job, candidate_ids: [candidateC], session_id: null, turn_request_id: null },
  });
  assert.ok(request);
  assert.deepEqual(request.source.candidate_ids, [candidateC]);
});

test("finalize with more than one candidate is rejected", () => {
  assert.equal(finalizeRequest({
    capability: "smart_import", input_hash: inputHash,
    source: { origin: "import_job", job_id: job, candidate_ids: [candidateA, candidateB], session_id: null, turn_request_id: null },
  }), null);
});

test("error code inherited from prototype is rejected", () => {
  assert.equal(usageError({ code: "constructor", message: "nope", recoverable: false, request_id: requestID }), null);
  assert.equal(usageError({ code: "toString", message: "nope", recoverable: false, request_id: requestID }), null);
});

test("invalid calendar date is rejected", () => {
  const bad = structuredClone(freeAccess);
  bad.server_time = "2026-02-30T00:00:00.000Z";
  assert.equal(accessResponse(bad), null);
});

test("frozen policy defaults match the versioned contract", () => {
  assert.equal(POLICY.schemaVersion, 1);
  assert.equal(POLICY.quotas.smart_import.free.limit, 5);
  assert.equal(POLICY.quotas.smart_import.free.period, "iso_week");
  assert.equal(POLICY.quotas.smart_import.premium.limit, 100);
  assert.equal(POLICY.quotas.smart_import.premium.period, "utc_month");
  assert.equal(POLICY.quotas.ai_edit.free.limit, 3);
  assert.equal(POLICY.quotas.ai_edit.free.period, "lifetime");
  assert.equal(POLICY.reservationTTLSeconds, 600);
});
