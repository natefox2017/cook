// Developer: gengyun
// Purpose: Exercise the actual dispatch, provider and draft modules using synthetic durable RPC interactions.

import assert from "node:assert/strict";
import test from "node:test";
import { createAIDraftDispatchWorker } from "./aiDraftDispatch.ts";
const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const S = "33333333-3333-4333-8333-333333333333";
const R = "44444444-4444-4444-8444-444444444444";
const F = "55555555-5555-4555-8555-555555555555";
const E = "66666666-6666-4666-8666-666666666666";
const H = "a".repeat(64);
const clone = structuredClone;
const defer = () => {
  let resolve;
  const promise = new Promise((r) => {
    resolve = r;
  });
  return { promise, resolve };
};
const input = () => ({ ownerID: A, sessionID: S, requestID: R });
const row = () => ({
  owner_id: A,
  session_id: S,
  request_id: R,
  fencing_token: F,
  based_revision: "1",
  context_hash: H,
  request_hash: H,
  lease_expires_at: new Date(Date.now() + 30000).toISOString(),
  state: "pending",
  dispatch_state: "predispatch",
  result: null,
  request_body: {
    request_id: R,
    expected_revision: "1",
    message: "Use the source wording.",
  },
  context_snapshot: {
    status: "needs_review",
    fields: {
      title: {
        raw_value: null,
        evidence_ids: [E],
        user_confirmed: false,
        origin: "extracted",
      },
      servings: {
        raw_value: "2",
        evidence_ids: [E],
        user_confirmed: true,
        origin: "extracted",
      },
      notes: { raw_value: "private journal", user_confirmed: false },
    },
    evidence: [{ id: E, excerpt: "Soup serves 2" }],
    review_fields: ["title"],
  },
});
const configuration = () => ({
  route: {
    route_key: "recipe_import_draft_v1",
    primary_model_id: "m",
    enabled: true,
    timeout_ms: 60000,
    max_retries: 3,
    max_output_tokens: 1000,
    temperature: null,
  },
  model: {
    id: "m",
    provider_id: "p",
    upstream_model_id: "synthetic-model",
    display_name: "Fixture",
    enabled: true,
    created_at: "2026-01-01T00:00:00Z",
  },
  provider: {
    id: "p",
    name: "Fixture",
    base_url: "https://synthetic.invalid/v1",
    secret_ref: "test-ref",
    enabled: true,
    updated_at: "2026-01-01T00:00:00Z",
  },
});
const content = () => ({
  questions: [],
  suggestions: [{
    path: "title",
    raw_value: "Soup",
    evidence_ids: [E],
    reason: "Source wording",
  }],
});
const envelope = (usage, inner = content()) => ({
  choices: [{
    finish_reason: "stop",
    message: { role: "assistant", content: JSON.stringify(inner) },
  }],
  usage: { total_tokens: usage },
});
const unavailable = { status: "unavailable", code: "PROVIDER_OUTCOME_UNKNOWN" };
function fixture() {
  const f = {
    turn: row(),
    calls: [],
    sent: [],
    usage: 25,
    inner: content(),
    recovered: undefined,
    marker: undefined,
    beforeMark: undefined,
    afterTransport: undefined,
    beforeFinish: undefined,
    config: configuration(),
    secret: "synthetic-secret",
    configCalls: 0,
    secretCalls: 0,
    errors: {},
    settled: undefined,
    transportWait: undefined,
    markerWait: undefined,
    secretWait: undefined,
  };
  f.storage = async (name, args, policy) => {
    f.calls.push({ name, args: clone(args), signal: policy.signal });
    if (f.errors[name]) throw new Error("private SQL / synthetic-secret");
    if (name === "recover_recipe_draft_turn") {
      return clone(f.recovered ?? { turn: f.turn });
    }
    if (name === "mark_recipe_draft_turn_dispatched") {
      await f.beforeMark?.(args);
      if (f.markerWait) await f.markerWait.promise;
      if (f.marker !== undefined) return clone(f.marker);
      if (
        f.turn.dispatch_state !== "predispatch" ||
        args.p_fencing_token !== f.turn.fencing_token ||
        f.turn.state !== "pending"
      ) return { code: "CLAIM_EXPIRED" };
      f.turn.dispatch_state = "dispatched_unknown";
      return { outcome: "dispatched", turn: clone(f.turn) };
    }
    await f.beforeFinish?.(args);
    if (
      args.p_fencing_token !== f.turn.fencing_token ||
      f.turn.state !== "pending" ||
      args.p_expected_dispatch_state !== f.turn.dispatch_state
    ) return { code: "CLAIM_EXPIRED" };
    f.settled = clone(args);
    f.turn.state = "terminal";
    f.turn.dispatch_state = "settled";
    f.turn.result = clone(args.p_result);
    f.turn.settled_tokens = args.p_expected_dispatch_state === "predispatch"
      ? 0
      : args.p_validated_usage ?? 4096;
    return { turn: clone(f.turn) };
  };
  f.options = {
    enabled: true,
    storage: f.storage,
    loadRouteConfiguration: async (signal) => {
      f.configCalls++;
      assert(signal instanceof AbortSignal);
      return clone(f.config);
    },
    resolveSecret: async (ref, signal) => {
      f.secretCalls++;
      assert.equal(ref, "test-ref");
      assert(signal instanceof AbortSignal);
      if (f.secretWait) await f.secretWait.promise;
      return f.secret;
    },
    safeTransport: async (request, policy) => {
      assert.equal(f.turn.dispatch_state, "dispatched_unknown");
      assert.equal(request.redirect, "error");
      assert.equal(policy.maxResponseBytes, 65536);
      f.sent.push({ request, policy });
      if (f.transportWait) await f.transportWait.promise;
      await f.afterTransport?.();
      return Response.json(envelope(f.usage, f.inner));
    },
  };
  f.run = (i = input(), options = {}) =>
    createAIDraftDispatchWorker({ ...f.options, ...options }).runTurn(i);
  return f;
}
const finishCalls = (f) =>
  f.calls.filter((c) => c.name === "finish_recipe_draft_turn");

test("default disabled, invalid inputs and invalid injected configuration do no work", async () => {
  const f = fixture();
  for (const enabled of [undefined, false, "true"]) {
    assert.deepEqual(await f.run(input(), { enabled }), { state: "disabled" });
  }
  for (
    const i of [{ ...input(), ownerID: "bad" }, {
      ...input(),
      extra: "client provider",
    }, { ...input(), signal: {} }]
  ) assert.equal((await f.run(i)).code, "INVALID_INPUT");
  for (const outerTimeoutMs of [0, 10001, 1.5]) {
    assert.equal(
      (await f.run(input(), { outerTimeoutMs })).code,
      "INVALID_CONFIGURATION",
    );
  }
  assert.equal(
    (await f.run(input(), { safeTransport: undefined })).code,
    "INVALID_CONFIGURATION",
  );
  assert.equal(f.calls.length, 0);
});

test("existing HTTP accepted pending dispatches once in committed RPC order, with exact wire projection and allowlist", async () => {
  const f = fixture();
  const result = await f.run();
  assert.equal(result.state, "terminal");
  assert.deepEqual(f.calls.map((c) => c.name), [
    "recover_recipe_draft_turn",
    "mark_recipe_draft_turn_dispatched",
    "finish_recipe_draft_turn",
  ]);
  assert.equal(f.sent.length, 1);
  assert.equal(f.secretCalls, 1);
  assert.equal(f.settled.p_validated_usage, 25);
  assert.equal(f.settled.p_expected_dispatch_state, "dispatched_unknown");
  assert.deepEqual(Object.keys(result.result).sort(), [
    "origin",
    "questions",
    "requires_approval",
    "status",
    "suggestions",
  ]);
  assert.equal(result.result.requires_approval, true);
  assert.equal(result.result.ownerID, undefined);
  assert.equal(result.result.requiresApproval, undefined);
  assert.deepEqual(f.calls[0].args, {
    p_owner_id: A,
    p_session_id: S,
    p_request_id: R,
    p_enabled: true,
  });
  const body = await f.sent[0].request.json();
  const prepared = JSON.parse(body.messages[1].content);
  assert.deepEqual(Object.keys(prepared.fields), ["title"]);
  assert.equal(JSON.stringify(result).includes("synthetic-secret"), false);
  assert.equal(JSON.stringify(result).includes("private journal"), false);
});

test("stable terminal and unknown pending recover without config, secrets or resend", async () => {
  for (const terminal of [true, false]) {
    const f = fixture();
    f.turn.dispatch_state = terminal ? "settled" : "dispatched_unknown";
    f.turn.state = terminal ? "terminal" : "pending";
    f.turn.result = terminal ? unavailable : null;
    const a = await f.run();
    const b = await f.run();
    assert.equal(a.state, terminal ? "terminal" : "pending");
    assert.deepEqual(a, b);
    assert.equal(f.configCalls, 0);
    assert.equal(f.secretCalls, 0);
    assert.equal(f.sent.length, 0);
    assert.equal(finishCalls(f).length, 0);
  }
});

test("ready stored terminal and actionable-empty preflight settle no-review without dispatch", async () => {
  for (const terminal of [true, false]) {
    const f = fixture();
    if (terminal) {
      f.turn.state = "terminal";
      f.turn.dispatch_state = "settled";
      f.turn.result = { status: "no_review_needed" };
    } else f.turn.context_snapshot.fields.title.user_confirmed = true;
    const r = await f.run();
    assert.deepEqual(r.result, { status: "no_review_needed" });
    assert.equal(f.configCalls, 0);
    assert.equal(f.sent.length, 0);
    if (!terminal) {
      assert.equal(f.settled.p_expected_dispatch_state, "predispatch");
      assert.equal(f.turn.settled_tokens, 0);
    }
  }
});

test("same-fence concurrent workers may prepare but only mark winner sends and finishes", async () => {
  const f = fixture();
  const gate = defer();
  let arrives = 0;
  f.beforeMark = async () => {
    if (++arrives === 2) gate.resolve();
    await gate.promise;
  };
  const results = await Promise.all([f.run(), f.run()]);
  assert.equal(f.sent.length, 1);
  assert.equal(finishCalls(f).length, 1);
  assert.equal(results.filter((r) => r.state === "terminal").length, 1);
  assert.equal(results.filter((r) => r.state === "pending").length, 1);
});

test("predispatch failure cannot finish another same-fence worker that won the marker", async () => {
  const f = fixture();
  f.config = null;
  f.beforeFinish = () => {
    f.turn.dispatch_state = "dispatched_unknown";
  };
  const r = await f.run();
  assert.equal(r.state, "pending");
  assert.equal(finishCalls(f)[0].args.p_expected_dispatch_state, "predispatch");
  assert.equal(f.turn.state, "pending");
  assert.equal(f.turn.result, null);
  assert.equal(f.sent.length, 0);
});

test("fresh per-attempt service isolates identical request UUID across sessions", async () => {
  const f = fixture();
  const worker = createAIDraftDispatchWorker(f.options);
  const first = await worker.runTurn(input());
  f.turn = row();
  f.turn.session_id = B;
  const second = await worker.runTurn({ ...input(), sessionID: B });
  assert.equal(first.state, "terminal");
  assert.equal(second.state, "terminal");
  assert.equal(f.sent.length, 2);
});

test("preflight internal invalid-field maps INVALID_INPUT without provider work", async () => {
  const f = fixture();
  f.turn.context_snapshot.fields.title.raw_value = 12;
  const r = await f.run();
  assert.deepEqual(r.result, { status: "rejected", code: "INVALID_INPUT" });
  assert.equal(f.configCalls, 0);
  assert.equal(f.sent.length, 0);
  assert.equal(f.settled.p_expected_dispatch_state, "predispatch");
  assert.equal(f.settled.p_validated_usage, null);
});

test("known preflight input budget code remains stable and costs zero", async () => {
  const f = fixture();
  f.turn.context_snapshot.evidence = Array.from(
    { length: 20 },
    (_, i) => ({ id: `excerpt-${i}`, excerpt: "x".repeat(1500) }),
  );
  f.turn.context_snapshot.fields.title.evidence_ids = [];
  f.turn.context_snapshot.fields.servings.evidence_ids = [];
  const r = await f.run();
  assert.deepEqual(r.result, { status: "rejected", code: "INPUT_BUDGET" });
  assert.equal(f.sent.length, 0);
  assert.equal(f.turn.settled_tokens, 0);
});

test("missing/disabled/mismatched route and secret failure stay predispatch unavailable", async () => {
  for (
    const change of [(f) => {
      f.config = null;
    }, (f) => {
      f.config.route.route_key = "unapproved";
    }, (f) => {
      f.config.provider.enabled = false;
    }, (f) => {
      f.config.route.primary_model_id = "foreign-model";
    }, (f) => {
      f.options.resolveSecret = async () => {
        throw new Error("private-key");
      };
    }, (f) => {
      f.secret = "bad\r\nkey";
    }]
  ) {
    const f = fixture();
    change(f);
    const r = await f.run();
    assert.deepEqual(r.result, {
      status: "unavailable",
      code: "PROVIDER_UNAVAILABLE",
    });
    assert.equal(f.sent.length, 0);
    assert.equal(f.settled.p_expected_dispatch_state, "predispatch");
    assert.equal(f.turn.settled_tokens, 0);
  }
});

test("usage boundaries and grounding rejection retain validated outer usage; unvalidated usage costs full", async () => {
  for (const usage of [0, 4096, -1, 4097, undefined]) {
    const f = fixture();
    f.usage = usage;
    const r = await f.run();
    assert.equal(r.state, "terminal");
    assert.equal(
      f.settled.p_validated_usage,
      usage === 0 || usage === 4096 ? usage : null,
    );
    assert.equal(
      f.turn.settled_tokens,
      usage === 0 || usage === 4096 ? usage : 4096,
    );
  }
  const f = fixture();
  f.inner.suggestions[0].raw_value = "invented quantity";
  const r = await f.run();
  assert.deepEqual(r.result, {
    status: "rejected",
    code: "INVALID_PROVIDER_OUTPUT",
  });
  assert.equal(f.settled.p_validated_usage, 25);
  assert.equal(f.turn.settled_tokens, 25);
  const forged = fixture();
  forged.inner.usage = { totalTokens: 0 };
  await forged.run();
  assert.equal(forged.settled.p_validated_usage, null);
  assert.equal(forged.turn.settled_tokens, 4096);
});

test("invalid owned RPC rows, revisions, hashes and stored wire results reject without dispatch", async () => {
  for (
    const change of [(t) => {
      t.owner_id = B;
    }, (t) => {
      t.session_id = B;
    }, (t) => {
      t.request_id = B;
    }, (t) => {
      t.fencing_token = "bad";
    }, (t) => {
      t.based_revision = 1;
    }, (t) => {
      t.context_hash = "bad";
    }, (t) => {
      t.request_body.message = "x".repeat(2001);
    }, (t) => {
      t.state = "terminal";
      t.dispatch_state = "settled";
      t.result = { status: "unavailable", code: "private error" };
    }, (t) => {
      t.state = "terminal";
      t.dispatch_state = "settled";
      t.result = { status: "no_review_needed", owner_id: B };
    }]
  ) {
    const f = fixture();
    change(f.turn);
    assert.equal((await f.run()).code, "INVALID_STORAGE_RESPONSE");
    assert.equal(f.sent.length, 0);
  }
  const f = fixture();
  f.recovered = { code: "NOT_FOUND" };
  assert.deepEqual(await f.run(), { state: "rejected", code: "NOT_FOUND" });
  f.recovered = { code: "SQL private error" };
  assert.equal((await f.run()).code, "INVALID_STORAGE_RESPONSE");
});

test("mark denial and failure never send or finish another winner; invalid marker is controlled", async () => {
  for (const mode of ["denied", "failure", "fence", "hash", "expired"]) {
    const f = fixture();
    if (mode === "denied") f.marker = { code: "CLAIM_EXPIRED" };
    if (mode === "failure") f.errors.mark_recipe_draft_turn_dispatched = true;
    if (["fence", "hash", "expired"].includes(mode)) {
      const t = row();
      t.dispatch_state = "dispatched_unknown";
      if (mode === "fence") t.fencing_token = B;
      if (mode === "hash") t.context_hash = "b".repeat(64);
      if (mode === "expired") t.lease_expires_at = new Date(0).toISOString();
      f.marker = { outcome: "dispatched", turn: t };
    }
    const r = await f.run();
    assert.equal(
      r.state,
      ["denied", "failure"].includes(mode) ? "pending" : "rejected",
    );
    assert.equal(f.sent.length, 0);
    assert.equal(finishCalls(f).length, 0);
  }
});

test("marker may atomically return stable terminal rather than permit transport", async () => {
  const f = fixture();
  const t = row();
  t.state = "terminal";
  t.dispatch_state = "settled";
  t.result = { status: "rejected", code: "STALE_REVISION" };
  f.marker = { turn: t };
  assert.deepEqual((await f.run()).result, t.result);
  assert.equal(f.sent.length, 0);
  assert.equal(finishCalls(f).length, 0);
});

test("bounded outer deadline covers secret and late mark; ignored abort cannot send later", async () => {
  for (const stage of ["secret", "mark"]) {
    const f = fixture();
    const gate = defer();
    if (stage === "secret") f.secretWait = gate;
    else f.markerWait = gate;
    const started = performance.now();
    const r = await f.run(input(), { outerTimeoutMs: 25 });
    assert.equal(r.state, "pending");
    assert.equal(r.recoveryNeeded, true);
    assert(performance.now() - started < 500);
    gate.resolve();
    await new Promise((resolve) => setTimeout(resolve, 5));
    assert.equal(f.sent.length, 0);
    assert.equal(finishCalls(f).length, 0);
  }
});

test("caller cancellation before start, predispatch and after marker discards late usage", async () => {
  for (const stage of ["before", "secret", "transport"]) {
    const f = fixture();
    const controller = new AbortController();
    const gate = defer();
    if (stage === "before") controller.abort();
    if (stage === "secret") f.secretWait = gate;
    if (stage === "transport") f.transportWait = gate;
    const operation = f.run({ ...input(), signal: controller.signal });
    if (stage !== "before") {
      while ((stage === "secret" ? f.secretCalls : f.sent.length) === 0) {
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
      controller.abort();
    }
    const r = await operation;
    assert.equal(r.state, "pending");
    gate.resolve();
    await new Promise((resolve) => setTimeout(resolve, 5));
    assert.equal(finishCalls(f).length, 0);
    assert.equal(f.sent.length, stage === "transport" ? 1 : 0);
    if (stage === "before") assert.equal(f.calls.length, 0);
  }
});

test("late old-fence result cannot finish replacement or recovered terminal", async () => {
  for (const terminal of [false, true]) {
    const f = fixture();
    f.afterTransport = () => {
      if (terminal) {
        f.turn.state = "terminal";
        f.turn.dispatch_state = "settled";
        f.turn.result = clone(unavailable);
      } else f.turn.fencing_token = B;
    };
    const r = await f.run();
    assert.equal(r.state, "pending");
    assert.equal(f.settled, undefined);
    assert.equal(f.sent.length, 1);
    assert.equal(finishCalls(f)[0].args.p_fencing_token, F);
    if (terminal) assert.deepEqual(f.turn.result, unavailable);
  }
});

test("finish storage uncertainty never claims durable success or exposes dependency error", async () => {
  const f = fixture();
  f.errors.finish_recipe_draft_turn = true;
  const r = await f.run();
  assert.equal(r.state, "pending");
  assert.equal(r.code, "RECOVERY_REQUIRED");
  assert.equal(JSON.stringify(r).includes("private"), false);
  assert.equal(f.sent.length, 1);
  assert.equal(f.turn.state, "pending");
});

test("group questions remain valid while uppercase UUID input is rejected", async () => {
  const f = fixture();
  f.turn.context_snapshot.fields = {
    "ingredients[0].amount": {
      raw_value: null,
      evidence_ids: [E],
      user_confirmed: false,
    },
  };
  f.turn.context_snapshot.review_fields = ["ingredients"];
  f.inner = {
    questions: [{
      path: "ingredients",
      question: "Which source wording should be kept?",
      evidence_ids: [E],
    }],
    suggestions: [],
  };
  assert.equal((await f.run()).result.status, "proposal");
  assert.equal(f.settled.p_result.questions[0].path, "ingredients");
  const upper = fixture();
  assert.equal(
    (await upper.run({
      ...input(),
      requestID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa".toUpperCase(),
    })).code,
    "INVALID_INPUT",
  );
  assert.equal(upper.calls.length, 0);
  const universal = fixture();
  universal.turn.request_id = "aaaaaaaa-aaaa-0000-0000-aaaaaaaaaaaa";
  universal.turn.request_body.request_id = universal.turn.request_id;
  assert.equal(
    (await universal.run({ ...input(), requestID: universal.turn.request_id }))
      .state,
    "terminal",
  );
});

test("route snapshot cannot change host, model or secret reference during secret await", async () => {
  const f = fixture();
  const config = configuration();
  f.options.loadRouteConfiguration = async () => config;
  f.options.resolveSecret = async (ref) => {
    assert.equal(ref, "test-ref");
    config.provider.base_url = "https://changed.invalid/v1";
    config.provider.secret_ref = "different-secret";
    config.model.upstream_model_id = "changed-model";
    return "synthetic-secret";
  };
  assert.equal((await f.run()).state, "terminal");
  assert.equal(
    f.sent[0].request.url,
    "https://synthetic.invalid/v1/chat/completions",
  );
  assert.equal((await f.sent[0].request.json()).model, "synthetic-model");
});

test("ignored transport abort cancels late response body without late usage or finish", async () => {
  const f = fixture();
  const gate = defer();
  let canceled = 0;
  f.options.safeTransport = async () => {
    f.sent.push({});
    await gate.promise;
    return new Response(
      new ReadableStream({
        cancel() {
          canceled++;
        },
      }),
    );
  };
  const result = await f.run(input(), { outerTimeoutMs: 25 });
  assert.equal(result.state, "pending");
  gate.resolve();
  await new Promise((resolve) => setTimeout(resolve, 5));
  assert.equal(canceled, 1);
  assert.equal(finishCalls(f).length, 0);
});

test("finish returned mismatched context, request hash or revision is rejected", async () => {
  for (const field of ["context_hash", "request_hash", "based_revision"]) {
    const f = fixture();
    const original = f.options.storage;
    f.options.storage = async (...args) => {
      const result = await original(...args);
      if (args[0] === "finish_recipe_draft_turn") {
        result.turn[field] = field === "based_revision" ? "2" : "b".repeat(64);
      }
      return result;
    };
    assert.equal((await f.run()).code, "INVALID_STORAGE_RESPONSE");
  }
});

test("outer deadline also bounds owned recover and finish RPC waits without accepting late terminal", async () => {
  for (
    const stage of ["recover_recipe_draft_turn", "finish_recipe_draft_turn"]
  ) {
    const f = fixture();
    const gate = defer();
    const original = f.options.storage;
    f.options.storage = async (...args) => {
      if (args[0] === stage) await gate.promise;
      return original(...args);
    };
    const r = await f.run(input(), { outerTimeoutMs: 25 });
    assert.equal(r.state, "pending");
    assert.equal(r.recoveryNeeded, true);
    gate.resolve();
    await new Promise((resolve) => setTimeout(resolve, 5));
    assert.equal(f.sent.length, stage === "recover_recipe_draft_turn" ? 0 : 1);
  }
});

test("marker terminal with different attempt binding is never accepted", async () => {
  for (
    const field of [
      "fencing_token",
      "context_hash",
      "request_hash",
      "based_revision",
    ]
  ) {
    const f = fixture();
    const t = row();
    t.state = "terminal";
    t.dispatch_state = "settled";
    t.result = clone(unavailable);
    t[field] = field === "fencing_token"
      ? B
      : field === "based_revision"
      ? "2"
      : "b".repeat(64);
    f.marker = { turn: t };
    assert.equal((await f.run()).code, "INVALID_STORAGE_RESPONSE");
    assert.equal(f.sent.length, 0);
    assert.equal(finishCalls(f).length, 0);
  }
});
