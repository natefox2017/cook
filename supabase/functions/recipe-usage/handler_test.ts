// Developer: gengyun
// Purpose: Prove the commercial usage HTTP contract with a fake adapter: routing, idempotency,
// error mapping and owner-gated source validation without any network or database.

import { strict as assert } from "node:assert";
import { handleRequest, type Dependencies } from "./handler.ts";
import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";

const OWNER = "d2977e89-94ab-4a2e-97eb-0f09b65f8d76";
const OP = "b0000000-0000-4000-8000-000000000001";
const JOB = "e0000000-0000-4000-8000-000000000005";
const SESSION = "f0000000-0000-4000-8000-000000000004";
const TURN = "f0000000-0000-4000-8000-000000000005";
const RECIPE = "c0000000-0000-4000-8000-000000000003";
const CANDIDATE = "candidate-v2-0123456789abcdef0123456789abcdef";

const importSource = {
  origin: "import_job",
  job_id: JOB,
  candidate_ids: [CANDIDATE],
  session_id: null,
  turn_request_id: null,
};
const editSource = {
  origin: "draft_approval",
  job_id: null,
  candidate_ids: null,
  session_id: SESSION,
  turn_request_id: TURN,
};
const receipt = {
  session_id: SESSION,
  turn_request_id: TURN,
  request_id: "f0000000-0000-4000-8000-000000000006",
  action: "accept",
  selected_paths: ["title"],
  applied_revision: "2",
};
const completedJob = {
  id: JOB,
  owner_id: OWNER,
  status: "completed",
  result: {
    recipe_id: RECIPE,
    status: "needs_review",
    source: {},
    fields: {},
    evidence: [],
    review_fields: [],
    candidate_recipes: [{
      candidate_id: CANDIDATE,
      title: "Soup",
      ingredients: [],
      steps: [],
      evidence_ids: [],
      review_fields: [],
    }],
  },
};
const session = { id: SESSION, owner_id: OWNER };
const editContext = {
  status: "needs_review",
  fields: { title: { raw_value: "Soup", evidence_ids: [], user_confirmed: true, origin: "extracted" } },
  evidence: [],
  review_fields: ["title"],
};
const editResult = {
  status: "proposal",
  origin: "AI_suggested",
  requires_approval: false,
  questions: [],
  suggestions: [{ path: "title", value: "Soup" }],
};
const turn = {
  owner_id: OWNER,
  session_id: SESSION,
  request_id: TURN,
  state: "terminal",
  dispatch_state: "settled",
  context_snapshot: editContext,
  result: editResult,
};
const approval = {
  owner_id: OWNER,
  session_id: SESSION,
  turn_request_id: TURN,
  action: "accept",
  selected_paths: ["title"],
  applied_revision: "2",
  receipt,
};
const editPayload = {
  context_snapshot: editContext,
  result: editResult,
  selected_paths: ["title"],
  applied_revision: "2",
};

const reservationBody = (inputHash: string) => ({
  operation_id: OP,
  capability: "smart_import",
  input_hash: inputHash,
  estimated_units: 1,
  source: importSource,
});

function request(path: string, body?: unknown): Request {
  return new Request("https://example.invalid" + path, {
    method: "POST",
    headers: {
      authorization: "Bearer synthetic-token",
      "content-type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function makeDeps(
  rpc: Dependencies["rpc"],
  job: unknown = completedJob,
): Dependencies {
  return {
    verifiedOwner: async () => ({ id: OWNER, isAnonymous: false }),
    isEnabled: async () => true,
    stage: "freeTest",
    loadOwnedJob: async () => (job as Record<string, unknown>) ?? null,
    loadOwnedSession: async () => (session as Record<string, unknown>),
    loadOwnedTurn: async () => (turn as Record<string, unknown>),
    loadOwnedApproval: async () => (approval as Record<string, unknown>),
    rpc,
  };
}

const RESERVATION = {
  operation_id: OP,
  owner_id: OWNER,
  capability: "smart_import",
  period_start: "2026-10-12T00:00:00.000Z",
  policy_version: 1,
  tier_at_reserve: "free",
  reserved_units: 1,
  status: "reserved",
  reserved_until: "2026-10-15T12:10:00.000Z",
};

Deno.test("reserve returns 201 and a validated reservation", async () => {
  const inputHash = await canonicalHash({ capability: "smart_import", source: importSource });
  const deps = makeDeps(async () => ({ code: "RESERVED", reservation: RESERVATION }));
  const res = await handleRequest(request("/recipe-usage/reservations", reservationBody(inputHash)), deps);
  assert.equal(res.status, 201);
  const body = await res.json();
  assert.equal(body.status, "reserved");
  assert.equal(body.operation_id, OP);
});

Deno.test("reserve replay returns 200 with the same reservation", async () => {
  const inputHash = await canonicalHash({ capability: "smart_import", source: importSource });
  const deps = makeDeps(async () => ({ code: "REPLAY", reservation: RESERVATION }));
  const res = await handleRequest(request("/recipe-usage/reservations", reservationBody(inputHash)), deps);
  assert.equal(res.status, 200);
});

Deno.test("reserve rejects a client-forged input_hash with 422", async () => {
  const deps = makeDeps(async () => ({ code: "RESERVED", reservation: RESERVATION }));
  const res = await handleRequest(request("/recipe-usage/reservations", reservationBody("a".repeat(64))), deps);
  assert.equal(res.status, 422);
  const body = await res.json();
  assert.equal(body.code, "INVALID_INPUT");
});

Deno.test("reserve surfaces QUOTA_EXCEEDED as 402 with Retry-After", async () => {
  const inputHash = await canonicalHash({ capability: "smart_import", source: importSource });
  const deps = makeDeps(async () => ({
    code: "QUOTA_EXCEEDED",
    reset_at: "2026-10-19T00:00:00.000Z",
  }));
  const res = await handleRequest(request("/recipe-usage/reservations", reservationBody(inputHash)), deps);
  assert.equal(res.status, 402);
  const body = await res.json();
  assert.equal(body.code, "QUOTA_EXCEEDED");
  assert.ok(res.headers.has("Retry-After"));
});

Deno.test("commit settles and returns committed_units 1", async () => {
  const inputHash = await canonicalHash({ capability: "smart_import", source: importSource });
  const deps = makeDeps(async () => ({
    code: "COMMITTED",
    operation_id: OP,
    period_start: "2026-10-12T00:00:00.000Z",
  }));
  const res = await handleRequest(
    request(`/recipe-usage/${OP}/commit`, { capability: "smart_import", input_hash: inputHash, source: importSource }),
    deps,
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, "committed");
  assert.equal(body.committed_units, 1);
});

Deno.test("smart_import finalize produces a server-owned recipe_id and payload_hash", async () => {
  const inputHash = await canonicalHash({ capability: "smart_import", source: importSource });
  const payloadHash = await canonicalHash(completedJob.result.candidate_recipes[0]);
  const deps = makeDeps(async () => ({
    code: "FINALIZED",
    operation_id: OP,
    recipe_id: RECIPE,
    payload_hash: payloadHash,
    period_start: "2026-10-12T00:00:00.000Z",
  }));
  const res = await handleRequest(
    request(`/recipe-usage/${OP}/finalize`, { capability: "smart_import", input_hash: inputHash, source: importSource }),
    deps,
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, "finalized");
  assert.equal(body.recipe_id, RECIPE);
  assert.equal(body.payload_hash, payloadHash);
});

Deno.test("ai_edit finalize requires an accepted approval and hashes the immutable turn snapshot", async () => {
  const inputHash = await canonicalHash({ capability: "ai_edit", source: editSource });
  const payloadHash = await canonicalHash(editPayload);
  const deps = makeDeps(async () => ({
    code: "FINALIZED",
    operation_id: OP,
    recipe_id: RECIPE,
    payload_hash: payloadHash,
    period_start: null,
  }));
  const res = await handleRequest(
    request(`/recipe-usage/${OP}/finalize`, { capability: "ai_edit", input_hash: inputHash, source: editSource }),
    deps,
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.payload_hash, payloadHash);
  assert.equal(body.period_start, null);
});

Deno.test("finalize rejects a foreign job source with NOT_FOUND", async () => {
  const inputHash = await canonicalHash({ capability: "smart_import", source: importSource });
  // The owned read returns null for a job the owner does not own.
  const deps = makeDeps(async () => ({ code: "FINALIZED" }), null);
  const res = await handleRequest(
    request(`/recipe-usage/${OP}/finalize`, { capability: "smart_import", input_hash: inputHash, source: importSource }),
    deps,
  );
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.code, "NOT_FOUND");
});

Deno.test("release returns the released reservation", async () => {
  const deps = makeDeps(async () => ({
    code: "RELEASED",
    reservation: { ...RESERVATION, status: "released" },
  }));
  const res = await handleRequest(request(`/recipe-usage/${OP}/release`), deps);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, "released");
});

Deno.test("ack returns acked for a committed operation", async () => {
  const deps = makeDeps(async () => ({ code: "ACKED", operation_id: OP }));
  const res = await handleRequest(request(`/recipe-usage/${OP}/ack`), deps);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, "acked");
});

Deno.test("missing authorization returns 401 AUTH_REQUIRED", async () => {
  const res = await handleRequest(
    new Request("https://example.invalid/recipe-usage/reservations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(reservationBody("a".repeat(64))),
    }),
    makeDeps(async () => ({})),
  );
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.equal(body.code, "AUTH_REQUIRED");
});

Deno.test("unknown action returns 404 NOT_FOUND", async () => {
  const deps = makeDeps(async () => ({}));
  const res = await handleRequest(request(`/recipe-usage/${OP}/bogus`), deps);
  assert.equal(res.status, 404);
});
