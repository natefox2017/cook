import test from "node:test";
import assert from "node:assert/strict";
import { handleRequest } from "./handler.ts";
import { canonicalHash, canonicalJSON } from "./canonicalJSON.ts";
const id = (n) =>
  `${n.toString(16).padStart(8, "0")}-0000-4000-8000-000000000000`;
const owner = id(1),
  other = id(2),
  jobID = id(3),
  sid = id(4),
  key = id(5),
  tid = id(6),
  aid = id(7),
  eid = id(8);
const hash = "a".repeat(64);
const base = () => ({
  status: "needs_review",
  fields: {
    title: {
      raw_value: null,
      evidence_ids: [eid],
      user_confirmed: false,
      origin: "extracted",
    },
  },
  evidence: [{ id: eid, excerpt: "Soup from the source" }],
  review_fields: ["title"],
});
const session = () => ({
  id: sid,
  owner_id: owner,
  job_id: jobID,
  client_request_id: key,
  revision: "1",
  source_fingerprint: "source:immutable",
  effective_context: base(),
  effective_context_hash: hash,
  overlay: {},
  reserved_tokens: 0,
  settled_tokens: 0,
  dispatch_count: 0,
  secret: "MUST_NOT_LEAK",
});
const proposal = () => ({
  status: "proposal",
  origin: "AI_suggested",
  requires_approval: true,
  questions: [],
  suggestions: [{
    path: "title",
    raw_value: "Soup",
    evidence_ids: [eid],
    reason: "Verbatim source",
  }],
});
const turn = () => ({
  owner_id: owner,
  session_id: sid,
  request_id: tid,
  based_revision: "1",
  context_hash: hash,
  state: "terminal",
  result: proposal(),
  secret: "MUST_NOT_LEAK",
});
const receipt = () => ({
  session_id: sid,
  turn_request_id: tid,
  request_id: aid,
  action: "accept",
  selected_paths: ["title"],
  applied_revision: "2",
});
function fixture() {
  const f = {
    s: session(),
    t: turn(),
    j: {
      id: jobID,
      owner_id: owner,
      status: "completed",
      source_fingerprint: "source:immutable",
      result: base(),
    },
    approval: null,
    replay: null,
    calls: [],
    reads: [],
  };
  const read = (name, value) => (...args) => {
    f.reads.push([name, ...args]);
    return Promise.resolve(typeof value === "function" ? value() : value);
  };
  f.deps = {
    verifiedOwner: async () => ({ id: owner, isAnonymous: false }),
    isEnabled: () => true,
    loadOwnedJob: read("job", () => f.j),
    loadOwnedSession: read("session", () => f.s),
    loadOwnedSessionByCreationKey: read("key", () => f.replay),
    loadOwnedTurn: read("turn", () => f.t),
    loadOwnedApprovalForTurn: read("approval", () => f.approval),
    rpc: async (name, args) => {
      f.calls.push([name, args]);
      if (f.rpc) return f.rpc(name, args);
      if (name === "create_recipe_draft_session") {
        return {
          outcome: "created",
          session: {
            ...f.s,
            effective_context: args.p_base_context,
            effective_context_hash: args.p_base_context_hash,
          },
        };
      }
      if (name === "claim_recipe_draft_turn") {
        return {
          outcome: "accepted",
          turn: { ...f.t, state: "pending", result: null },
        };
      }
      return { receipt: receipt() };
    },
  };
  return f;
}
const url = (path) => "https://unit.test/recipe-draft-sessions" + path;
async function send(
  f,
  path = "",
  method = "POST",
  body = { job_id: jobID, client_request_id: key },
  headers = { authorization: "Bearer signed-synthetic" },
) {
  const request = new Request(url(path), {
    method,
    headers,
    ...(method === "POST"
      ? { body: typeof body === "string" ? body : JSON.stringify(body) }
      : {}),
  });
  const response = await handleRequest(request, f.deps);
  return {
    status: response.status,
    body: await response.json(),
    headers: response.headers,
  };
}
const turnBody = () => ({
  request_id: tid,
  expected_revision: "1",
  message: "Please review",
});
const approvalBody = () => ({
  request_id: aid,
  expected_revision: "1",
  action: "accept",
  selected_paths: ["title"],
});
test("five routes project minimal wire, exact owner RPC args and hash envelope", async () => {
  const f = fixture();
  f.j.result.fields.title.normalized_value = "keep original";
  f.j.result.private_metadata = { confidence: 0.2 };
  let r = await send(f);
  assert.equal(r.status, 201);
  assert.equal(r.body.session_id, sid);
  assert.ok(r.headers.get("access-control-allow-origin"));
  assert.equal(r.body.secret, undefined);
  const args = f.calls[0][1];
  assert.equal(args.p_owner_id, owner);
  assert.strictEqual(args.p_expected_job_result, f.j.result);
  assert.equal(f.j.result.fields.title.normalized_value, "keep original");
  assert.equal(
    args.p_base_context_hash,
    await canonicalHash({
      job_id: jobID,
      source_fingerprint: "source:immutable",
      revision: "1",
      context: {
        status: "needs_review",
        fields: base().fields,
        evidence: base().evidence,
        reviewFields: ["title"],
      },
    }),
  );
  r = await send(f, "/" + sid, "GET");
  assert.equal(r.status, 200);
  assert.deepEqual(
    Object.keys(r.body).sort(),
    [
      "session_id",
      "job_id",
      "client_request_id",
      "revision",
      "source_fingerprint",
      "context_hash",
      "context",
      "overlay",
      "budget",
    ].sort(),
  );
  r = await send(f, "/" + sid + "/turns", "POST", turnBody());
  assert.equal(r.status, 202);
  assert.equal(r.body.state, "pending");
  assert.equal(r.body.decision, null);
  assert.equal(
    f.calls.at(-1)[1].p_request_hash,
    await canonicalHash(turnBody()),
  );
  assert.equal(f.calls.at(-1)[1].p_expected_revision, "1");
  r = await send(f, "/" + sid + "/turns/" + tid, "GET");
  assert.equal(r.status, 200);
  assert.equal(r.body.result.status, "proposal");
  r = await send(
    f,
    "/" + sid + "/turns/" + tid + "/approval",
    "POST",
    approvalBody(),
  );
  assert.equal(r.status, 200);
  const approval = f.calls.at(-1)[1];
  assert.equal(approval.p_next_context.fields.title.raw_value, "Soup");
  assert.equal(approval.p_next_context.fields.title.user_confirmed, true);
  assert.equal(approval.p_next_context.status, "ready");
  assert.deepEqual(approval.p_next_context.review_fields, []);
  assert.equal(
    approval.p_next_context_hash,
    await canonicalHash({
      job_id: jobID,
      source_fingerprint: "source:immutable",
      revision: "2",
      context: {
        status: "ready",
        fields: approval.p_next_context.fields,
        evidence: base().evidence,
        reviewFields: [],
      },
    }),
  );
  assert.ok(
    f.calls.every(([name]) =>
      [
        "create_recipe_draft_session",
        "claim_recipe_draft_turn",
        "approve_recipe_draft_turn",
      ].includes(name)
    ),
  );
});
test("authentication, anonymous, disabled and exact route boundaries precede reads", async () => {
  for (
    const auth of [null, { id: owner, isAnonymous: true }, {
      id: "bad",
      isAnonymous: false,
    }]
  ) {
    const f = fixture();
    f.deps.verifiedOwner = async () => auth;
    assert.equal((await send(f)).status, 401);
    assert.equal(f.reads.length, 0);
  }
  const f = fixture();
  f.deps.verifiedOwner = async () => {
    throw Error("secret");
  };
  assert.equal((await send(f)).status, 401);
  const noHeader = fixture();
  assert.equal((await send(noHeader, "", "POST", {}, {})).status, 401);
  assert.equal(noHeader.reads.length, 0);
  for (const enabled of [false, undefined, "true", 1]) {
    const d = fixture();
    d.deps.isEnabled = () => enabled;
    assert.equal((await send(d)).body.code, "DRAFT_DISABLED");
    assert.equal(d.calls.length, 0);
    assert.equal(d.reads.length, 0);
    assert.equal((await send(d, "/" + sid, "GET")).status, 200);
  }
  for (
    const path of [
      "/",
      "/" + sid + "/",
      "//" + sid,
      "/" + sid + "/turns/" + tid + "/bad",
    ]
  ) assert.equal((await send(f, path, "GET")).status, 404);
  const preflight = await handleRequest(
    new Request(url(""), { method: "OPTIONS" }),
    fixture().deps,
  );
  assert.equal(preflight.status, 200);
});
test("strict bodies reject duplicates, authority, malformed UTF8 and revision/message paths", async () => {
  for (
    const body of [
      '{"job_id":"' + jobID + '","job_id":"' + jobID +
      '","client_request_id":"' + key + '"}',
      { job_id: jobID, client_request_id: key, owner_id: owner },
      null,
      [],
      { job_id: jobID.toUpperCase(), client_request_id: key },
    ]
  ) {
    // Ensure uppercase fixture contains a-f instead of only digits.
    if (body?.job_id === jobID.toUpperCase() && body.job_id === jobID) {
      body.job_id = "ABCDEFAB-0000-4000-8000-000000000000";
    }
    const f = fixture();
    assert.equal((await send(f, "", "POST", body)).status, 422);
    assert.equal(f.calls.length, 0);
  }
  for (
    const change of [
      { expected_revision: 1 },
      { expected_revision: "01" },
      { expected_revision: "9223372036854775808" },
      { message: "x".repeat(2001) },
      { message: "\ud800" },
      { provider: "fake" },
      { context: {} },
    ]
  ) {
    const f = fixture();
    assert.equal(
      (await send(f, "/" + sid + "/turns", "POST", {
        ...turnBody(),
        ...change,
      })).status,
      422,
    );
    assert.equal(f.calls.length, 0);
  }
  for (
    const body of [
      { ...approvalBody(), selected_paths: [] },
      { ...approvalBody(), action: "reject" },
      { ...approvalBody(), selected_paths: ["title", "title"] },
      { ...approvalBody(), selected_paths: ["ingredients[100].name"] },
    ]
  ) {
    assert.equal(
      (await send(
        fixture(),
        "/" + sid + "/turns/" + tid + "/approval",
        "POST",
        body,
      )).status,
      422,
    );
  }
});
test("owner and lineage mismatch across all read paths never gains access", async () => {
  for (const target of ["j", "s", "t"]) {
    const f = fixture();
    f[target].owner_id = other;
    const r = await send(
      f,
      target === "j"
        ? ""
        : target === "s"
        ? "/" + sid
        : "/" + sid + "/turns/" + tid,
      target === "j" ? "POST" : "GET",
    );
    assert.equal(r.status, 404);
    assert.equal(r.body.message, "Resource not found.");
    assert.equal(f.calls.length, 0);
  }
  const f = fixture();
  f.deps.verifiedOwner = async () => ({ id: other, isAnonymous: false });
  assert.equal((await send(f, "/" + sid, "GET")).status, 404);
  assert.equal(f.reads[0][1], other);
  for (const change of [{ owner_id: other }, { client_request_id: id(100) }]) {
    const g = fixture();
    g.replay = { ...g.s, ...change };
    assert.equal((await send(g)).status, 404);
  }
  const g = fixture();
  g.t.session_id = id(100);
  assert.equal((await send(g, "/" + sid + "/turns/" + tid, "GET")).status, 404);
});
test("creation replay precedes changed job readiness, unsupported flags and creation race", async () => {
  for (
    const change of [{ status: "failed" }, { result: null }, {
      result: { ...base(), review_fields: ["recipe_selection"] },
    }]
  ) {
    const f = fixture();
    Object.assign(f.j, change);
    f.replay = f.s;
    const r = await send(f);
    assert.equal(r.status, 200);
    assert.equal(f.calls.length, 0);
    assert.deepEqual(f.reads.map((r) => r[0]), ["key"]);
  }
  const f = fixture();
  f.replay = { ...f.s, job_id: id(20) };
  assert.equal((await send(f)).body.code, "IDEMPOTENCY_CONFLICT");
  const race = fixture();
  race.rpc = () => ({ outcome: "replay", session: race.s });
  assert.equal((await send(race)).status, 200);
  const broken = fixture();
  broken.deps.loadOwnedSessionByCreationKey = async () => {
    throw Error("secret");
  };
  assert.equal((await send(broken)).status, 500);
  assert.equal(broken.calls.length, 0);
});
test("context validation rejects unsupported paths, evidence and stale confirmed flags without writes", async () => {
  for (
    const mutate of [
      (j) => j.status = "pending",
      (j) => j.result.review_fields = ["recipe_selection"],
      (j) => j.result.fields.title.evidence_ids = [id(100)],
      (j) => j.result.evidence[0].excerpt = null,
      (j) => j.result.evidence[0].excerpt = "x".repeat(1501),
      (j) => j.result.fields.title.raw_value = "x".repeat(1501),
      (j) => j.result.fields.title.user_confirmed = true,
      (j) => j.result.fields["notes"] = j.result.fields.title,
    ]
  ) {
    const f = fixture();
    mutate(f.j);
    assert.ok([409, 422].includes((await send(f)).status));
    assert.equal(f.calls.length, 0);
  }
  const f = fixture();
  f.j.result.evidence = Array.from(
    { length: 14 },
    (_, i) => ({ id: id(100 + i), excerpt: "x".repeat(1500) }),
  );
  f.j.result.fields.title.evidence_ids = [];
  assert.equal((await send(f)).status, 422);
});
test("pure missing group with empty fields remains actionable and durable pending", async () => {
  const f = fixture();
  const ctx = {
    status: "needs_review",
    fields: {},
    evidence: [],
    review_fields: ["title", "ingredients", "steps"],
  };
  f.j.result = ctx;
  f.s.effective_context = ctx;
  assert.equal((await send(f)).status, 201);
  assert.deepEqual(Object.keys(f.calls[0][1].p_base_context.fields), []);
  assert.equal((await send(f, "/" + sid, "GET")).status, 200);
  const r = await send(f, "/" + sid + "/turns", "POST", turnBody());
  assert.equal(r.status, 202);
  assert.equal(r.body.state, "pending");
});
test("large fully confirmed ready context is not confused with provider/body 32768 limit", async () => {
  const f = fixture(),
    ctx = { status: "ready", fields: {}, evidence: [], review_fields: [] };
  for (let i = 0; i < 100; i++) {
    ctx.fields[`steps[${i}].instruction`] = {
      raw_value: "x".repeat(1000),
      evidence_ids: [],
      user_confirmed: true,
      origin: "user",
    };
  }
  assert.ok(Buffer.byteLength(JSON.stringify(ctx)) > 32768);
  assert.ok(Buffer.byteLength(JSON.stringify(ctx)) <= 1048576);
  f.j.result = ctx;
  f.s.effective_context = ctx;
  assert.equal((await send(f)).status, 201);
  f.rpc = (name, args) => ({
    outcome: "accepted",
    turn: {
      ...f.t,
      state: "terminal",
      result: { status: "no_review_needed" },
      reserved_tokens: 0,
      dispatch_state: "settled",
    },
  });
  const r = await send(f, "/" + sid + "/turns", "POST", turnBody());
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.result, { status: "no_review_needed" });
  assert.equal(f.s.reserved_tokens, 0);
  assert.equal(f.s.dispatch_count, 0);
  const huge = fixture();
  huge.j.result.fields.title.raw_value = "x".repeat(1048577);
  assert.equal((await send(huge)).status, 422);
  assert.equal(huge.calls.length, 0);
});
test("turn replay permits old revision and supplements separate authoritative decision", async () => {
  const f = fixture();
  f.s.revision = "2";
  f.rpc = () => ({ outcome: "replay", turn: f.t });
  f.approval = {
    owner_id: owner,
    session_id: sid,
    turn_request_id: tid,
    request_id: aid,
    action: "accept",
    selected_paths: ["title"],
    applied_revision: "2",
    receipt: receipt(),
  };
  const before = structuredClone(f.t.result);
  const r = await send(f, "/" + sid + "/turns", "POST", turnBody());
  assert.equal(r.status, 200);
  assert.equal(r.body.decision.request_id, aid);
  assert.deepEqual(r.body.result, before);
  assert.equal(f.calls[0][1].p_expected_revision, "1");
  f.approval.owner_id = other;
  assert.equal((await send(f, "/" + sid + "/turns/" + tid, "GET")).status, 404);
  const pending = fixture();
  pending.t.state = "pending";
  pending.t.result = null;
  assert.equal(
    (await send(pending, "/" + sid + "/turns/" + tid, "GET")).body.decision,
    null,
  );
});
test("decimal max and BigInt values remain exact while rounded numeric revisions fail", async () => {
  for (const rev of ["9223372036854775807", 9223372036854775807n]) {
    const f = fixture();
    f.s.revision = rev;
    f.t.based_revision = rev;
    assert.equal(
      (await send(f, "/" + sid, "GET")).body.revision,
      "9223372036854775807",
    );
    const body = { ...turnBody(), expected_revision: "9223372036854775807" };
    assert.equal(
      (await send(f, "/" + sid + "/turns", "POST", body)).status,
      202,
    );
    assert.equal(f.calls.at(-1)[1].p_expected_revision, "9223372036854775807");
    f.rpc = () => ({ code: "REVISION_EXHAUSTED" });
    const r = await send(f, "/" + sid + "/turns/" + tid + "/approval", "POST", {
      ...approvalBody(),
      expected_revision: "9223372036854775807",
    });
    assert.equal(r.body.code, "REVISION_EXHAUSTED");
    assert.equal(f.calls.at(-1)[1].p_next_context, null);
  }
  for (const rev of [1, 9007199254740992, "0", "9223372036854775808"]) {
    const f = fixture();
    f.s.revision = rev;
    assert.equal((await send(f, "/" + sid, "GET")).status, 500);
  }
});
test("approval replay is checked by SQL before current CAS/proposal, reject retains source", async () => {
  const f = fixture();
  f.s.revision = "3";
  f.t.result = { status: "unavailable", code: "PROVIDER_TIMEOUT" };
  f.rpc = () => ({ outcome: "replay", receipt: receipt() });
  assert.equal(
    (await send(
      f,
      "/" + sid + "/turns/" + tid + "/approval",
      "POST",
      approvalBody(),
    )).status,
    200,
  );
  assert.equal(f.calls[0][1].p_next_context, null);
  const reject = fixture();
  reject.rpc = (name, args) => ({
    receipt: { ...receipt(), action: "reject", selected_paths: [] },
  });
  assert.equal(
    (await send(reject, "/" + sid + "/turns/" + tid + "/approval", "POST", {
      ...approvalBody(),
      action: "reject",
      selected_paths: [],
    })).status,
    200,
  );
  assert.equal(
    canonicalJSON(reject.calls[0][1].p_next_context),
    canonicalJSON(base()),
  );
  for (
    const change of [{ selected_paths: ["servings"] }, {
      selected_paths: ["title"],
      confirmed: true,
    }]
  ) {
    const bad = fixture();
    if (change.confirmed) {
      bad.s.effective_context.fields.title.user_confirmed = true;
      bad.s.effective_context.review_fields = [];
      bad.s.effective_context.status = "ready";
    }
    assert.equal(
      (await send(bad, "/" + sid + "/turns/" + tid + "/approval", "POST", {
        ...approvalBody(),
        selected_paths: change.selected_paths,
      })).status,
      422,
    );
    assert.equal(bad.calls.length, 0);
  }
});
test("approval group retains explicit nonexistent sibling instead of declaring ready", async () => {
  const f = fixture();
  const path = "ingredients[0].amount";
  f.s.effective_context = {
    status: "needs_review",
    fields: {
      [path]: {
        raw_value: null,
        evidence_ids: [eid],
        user_confirmed: false,
        origin: "extracted",
      },
    },
    evidence: base().evidence,
    review_fields: ["ingredients", "ingredients[1].name"],
  };
  f.t.result.suggestions[0].path = path;
  f.rpc = (name, args) => ({
    receipt: { ...receipt(), selected_paths: [path] },
  });
  assert.equal(
    (await send(f, "/" + sid + "/turns/" + tid + "/approval", "POST", {
      ...approvalBody(),
      selected_paths: [path],
    })).status,
    200,
  );
  const next = f.calls[0][1].p_next_context;
  assert.deepEqual(next.review_fields, ["ingredients", "ingredients[1].name"]);
  assert.equal(next.status, "needs_review");
});
test("known RPC error mapping, exceptions and malformed wire fail without secrets", async () => {
  const codes = {
    NOT_FOUND: 404,
    JOB_NOT_READY: 409,
    STALE_REVISION: 409,
    IDEMPOTENCY_CONFLICT: 409,
    TURN_ALREADY_DECIDED: 409,
    REVISION_EXHAUSTED: 409,
    INVALID_INPUT: 422,
    INVALID_EVIDENCE: 422,
    INVALID_REVIEW_PATH: 422,
    BUDGET_EXHAUSTED: 429,
    DRAFT_DISABLED: 503,
    PROVIDER_UNAVAILABLE: 503,
    REQUEST_CONFLICT: 409,
    UNKNOWN_SECRET: 500,
  };
  for (const [code, status] of Object.entries(codes)) {
    const f = fixture();
    f.rpc = () => ({ code, detail: "SECRET SQL" });
    const r = await send(f);
    assert.equal(r.status, status);
    assert.equal(JSON.stringify(r.body).includes("SECRET"), false);
    assert.match(r.body.request_id, /^[0-9a-f-]{36}$/);
  }
  for (
    const output of [null, {}, { outcome: "queued", session: session() }, {
      outcome: "created",
      session: { ...session(), effective_context_hash: "bad" },
    }]
  ) {
    const f = fixture();
    f.rpc = () => output;
    assert.equal((await send(f)).status, 500);
  }
  const f = fixture();
  f.deps.rpc = async () => {
    throw Error("secret");
  };
  assert.equal((await send(f)).status, 500);
  for (
    const result of [
      { status: "unknown" },
      { ...proposal(), origin: "model" },
      {
        ...proposal(),
        suggestions: [{
          path: "private",
          raw_value: "x",
          evidence_ids: [],
          reason: "bad",
        }],
      },
    ]
  ) {
    const g = fixture();
    g.t.result = result;
    assert.equal(
      (await send(g, "/" + sid + "/turns/" + tid, "GET")).status,
      500,
    );
  }
});

test("result code objects cannot execute coercion or escape wire as objects", async () => {
  const f = fixture();
  let calls = 0;
  f.t.result = {
    status: "rejected",
    code: {
      toString() {
        calls++;
        return "INVALID_INPUT";
      },
    },
  };
  assert.equal((await send(f, "/" + sid + "/turns/" + tid, "GET")).status, 500);
  assert.equal(calls, 0);
});

test("approval current expected revision with stale turn reaches authoritative CAS", async () => {
  for (
    const [change, code] of [
      [{ based_revision: "1" }, "TURN_ALREADY_DECIDED"],
      [{ based_revision: "2", context_hash: "b".repeat(64) }, "STALE_REVISION"],
    ]
  ) {
    const f = fixture();
    f.s.revision = "2";
    f.s.effective_context.fields.title.user_confirmed = true;
    f.s.effective_context.fields.title.raw_value = "Soup";
    f.s.effective_context.review_fields = [];
    f.s.effective_context.status = "ready";
    Object.assign(f.t, change);
    f.rpc = () => ({ code });
    const r = await send(f, "/" + sid + "/turns/" + tid + "/approval", "POST", {
      ...approvalBody(),
      expected_revision: "2",
    });
    assert.equal(r.status, 409);
    assert.equal(r.body.code, code);
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0][1].p_next_context, null);
  }
  const f = fixture();
  f.t.state = "pending";
  f.t.result = null;
  f.rpc = () => ({ code: "INVALID_INPUT" });
  assert.equal(
    (await send(
      f,
      "/" + sid + "/turns/" + tid + "/approval",
      "POST",
      approvalBody(),
    )).status,
    422,
  );
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0][1].p_next_context, null);
});
