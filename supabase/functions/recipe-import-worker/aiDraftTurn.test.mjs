// Developer: gengyun
// Purpose: Exercise disabled, bounded and extractive draft turns with original offline provider fixtures.

import assert from "node:assert/strict";
import test from "node:test";
import { createAIDraftTurnService } from "./aiDraftTurn.ts";

const context = () => ({
  ownerID: "owner-A", currentRevision: "revision-1", status: "needs_review",
  fields: {
    "ingredients[0].amount": { raw_value: null, evidence_ids: ["e1"], user_confirmed: false },
    "ingredients[1].amount": { raw_value: "a little", evidence_ids: ["e1"], user_confirmed: true },
    notes: { raw_value: "private journal never sent" },
  },
  evidence: [{ id: "e1", excerpt: "Use salt to taste and a little butter.", secret: "never forward" }],
  reviewFields: ["ingredients"],
  source: { credential: "never forward" },
});
const request = (requestID = "r1") => ({ ownerID: "owner-A", expectedRevision: "revision-1", requestID, message: "What does the source say?" });
const output = () => ({
  questions: [{ path: "ingredients[0].amount", question: "Would you like to keep the source wording?", evidence_ids: ["e1"] }],
  suggestions: [{ path: "ingredients[0].amount", raw_value: "salt to taste", evidence_ids: ["e1"], reason: "Original source wording; exact amount remains unknown." }],
  usage: { totalTokens: 25 },
});
const service = (provider = async () => output(), options = {}) => createAIDraftTurnService({ enabled: true, provider, ...options });
const rejected = async (s, r = request(), c = context(), code) => {
  const result = await s.generateTurn(r, c);
  assert.equal(result.status, "rejected");
  if (code) assert.equal(result.code, code);
};
const defer = () => { let resolve; const promise = new Promise((r) => { resolve = r; }); return { promise, resolve }; };

test("disabled and invalid configuration never call the provider", async () => {
  let calls = 0;
  for (const enabled of [undefined, false, "true", 1]) {
    const s = createAIDraftTurnService({ enabled, provider: async () => { calls++; return output(); } });
    assert.equal((await s.generateTurn(request(), context())).status, "disabled");
  }
  for (const timeoutMs of [0, 10001, 1.5, NaN]) await rejected(service(async () => { calls++; }, { timeoutMs }), undefined, undefined, "INVALID_CONFIGURATION");
  await rejected(createAIDraftTurnService({ enabled: true }), undefined, undefined, "INVALID_CONFIGURATION");
  assert.equal(calls, 0);
});

test("extractive proposal is explicit, private, cloned and does not mutate source", async () => {
  const c = context(); const r = request(); const original = JSON.stringify({ c, r });
  let sent; const raw = output();
  const result = await service(async (input) => { sent = input; input.fields["ingredients[0].amount"].raw_value = "provider mutation"; return raw; }).generateTurn(r, c);
  assert.equal(result.status, "proposal");
  assert.equal(result.origin, "AI_suggested"); assert.equal(result.requiresApproval, true);
  assert.equal(result.ownerID, "owner-A"); assert.equal(result.revision, "revision-1"); assert.equal(result.requestID, "r1");
  assert.equal(JSON.stringify({ c, r }), original);
  assert.deepEqual(Object.keys(sent.fields), ["ingredients[0].amount"]);
  assert.deepEqual(sent.evidence, [{ id: "e1", excerpt: c.evidence[0].excerpt }]);
  assert.equal(JSON.stringify(sent).includes("never forward"), false);
  raw.suggestions[0].raw_value = "changed";
  assert.equal(result.suggestions[0].raw_value, "salt to taste");
});

test("ready and entirely confirmed groups require no provider", async () => {
  let calls = 0; const s = service(async () => { calls++; return output(); });
  const ready = context(); ready.status = "ready";
  assert.equal((await s.generateTurn(request(), ready)).status, "no_review_needed");
  const confirmed = context(); confirmed.fields["ingredients[0].amount"].user_confirmed = true;
  assert.equal((await s.generateTurn(request(), confirmed)).status, "no_review_needed");
  const unsupported = context(); unsupported.reviewFields = ["recipe_selection"];
  assert.equal((await s.generateTurn(request(), unsupported)).status, "no_review_needed");
  assert.equal(calls, 0);
});

test("identity, revision, malformed input and field/evidence budgets reject before provider", async () => {
  let calls = 0; const s = service(async () => { calls++; return output(); });
  const variants = [
    [null, context()], [{ ...request(), ownerID: "owner-B" }, context()],
    [{ ...request(), expectedRevision: "revision-2" }, context()],
    [{ ...request(), requestID: "" }, context()], [{ ...request(), message: "x".repeat(2001) }, context()],
    [{ ...request(), notes: "forbidden" }, context()],
    [request(), { ...context(), fields: null }],
    [request(), { ...context(), evidence: Array.from({ length: 61 }, (_, i) => ({ id: `e${i}`, excerpt: "salt" })) }],
    [request(), { ...context(), evidence: [{ id: "e1", excerpt: "x".repeat(1501) }] }],
    [request(), { ...context(), evidence: [{ id: "e1", excerpt: "salt" }, { id: "e1", excerpt: "salt" }] }],
    [request(), { ...context(), reviewFields: [null] }],
    [request(), { ...context(), fields: { title: { raw_value: "x", user_confirmed: "true" } } }],
    [request(), { ...context(), fields: { title: { raw_value: "x", user_confirmed: false, evidence_ids: ["missing"] } } }],
  ];
  for (const [r, c] of variants) await rejected(s, r, c);
  const tooMany = context(); tooMany.fields = Object.fromEntries(Array.from({ length: 101 }, (_, i) => [`field${i}`, {}]));
  await rejected(s, request(), tooMany);
  const total = context(); total.evidence = Array.from({ length: 14 }, (_, i) => ({ id: `e${i}`, excerpt: "x".repeat(1500) }));
  total.fields = {}; await rejected(s, request(), total, "INPUT_BUDGET");
  assert.equal(calls, 0);
});

test("confirmed sibling and exact review paths cannot be targeted", async () => {
  const confirmed = output(); confirmed.suggestions[0].path = "ingredients[1].amount";
  await rejected(service(async () => confirmed), undefined, undefined, "INVALID_PROVIDER_OUTPUT");
  const c = context(); c.reviewFields = ["ingredients[0].amount"];
  c.fields["ingredients[2].amount"] = { user_confirmed: false };
  const sibling = output(); sibling.suggestions[0].path = "ingredients[2].amount";
  await rejected(service(async () => sibling), request(), c, "INVALID_PROVIDER_OUTPUT");
});

test("invented precision, unknown IDs/paths, duplicates, private and oversized outputs fail closed", async () => {
  const mutations = [
    (o) => { o.suggestions[0].raw_value = "5 grams salt"; },
    (o) => { o.suggestions[0].evidence_ids = ["missing"]; },
    (o) => { o.suggestions[0].evidence_ids = []; },
    (o) => { o.suggestions[0].evidence_ids = ["e1", "e1"]; },
    (o) => { o.suggestions[0].path = "owner"; },
    (o) => { o.suggestions[0].secret = "unexpected"; },
    (o) => { o.notes = "private"; },
    (o) => { o.suggestions.push(structuredClone(o.suggestions[0])); },
    (o) => { o.suggestions[0].raw_value = " "; },
    (o) => { o.suggestions[0].raw_value = "x".repeat(1501); },
    (o) => { o.suggestions[0].reason = "x".repeat(501); },
    (o) => { o.questions = Array.from({ length: 4 }, () => o.questions[0]); },
    (o) => { o.questions[0].question = "x".repeat(301); },
    (o) => { o.questions[0].path = "steps[99].instruction"; },
    (o) => { o.suggestions = Array.from({ length: 21 }, () => o.suggestions[0]); },
    (o) => { o.usage.totalTokens = 4097; }, (o) => { o.usage.totalTokens = -1; },
    (o) => { o.usage.totalTokens = 1.5; }, (o) => { o.usage.totalTokens = "25"; },
    (o) => { delete o.usage; },
  ];
  for (const mutate of mutations) { const o = output(); mutate(o); await rejected(service(async () => o), undefined, undefined, "INVALID_PROVIDER_OUTPUT"); }
});

test("UTF8 byte limits are independent of character limits and token boundary is inclusive", async () => {
  const c = context(); c.fields = {};
  c.evidence = Array.from({ length: 11 }, (_, i) => ({ id: `e${i}`, excerpt: "界".repeat(1000) }));
  let calls = 0; await rejected(service(async () => { calls++; return output(); }), request(), c, "INPUT_BUDGET");
  assert.equal(calls, 0);
  const o = output(); o.usage.totalTokens = 4096;
  assert.equal((await service(async () => o).generateTurn(request(), context())).status, "proposal");
});

test("same-turn concurrency and replay call once and return isolated copies", async () => {
  const gate = defer(); let calls = 0;
  const s = service(async () => { calls++; await gate.promise; return output(); });
  const first = s.generateTurn(request(), context()); const second = s.generateTurn(request(), context());
  await Promise.resolve(); assert.equal(calls, 1); gate.resolve();
  const [a, b] = await Promise.all([first, second]); a.suggestions[0].raw_value = "modified";
  assert.equal(b.suggestions[0].raw_value, "salt to taste");
  const replay = await s.generateTurn(request(), context()); assert.equal(calls, 1); assert.equal(replay.suggestions[0].raw_value, "salt to taste");
  await rejected(s, { ...request(), message: "different" }, context(), "REQUEST_CONFLICT");
});

test("32-entry capacity bounds pending and successful cache, failures release capacity", async () => {
  const s = service(); for (let i = 0; i < 32; i++) assert.equal((await s.generateTurn(request(`r${i}`), context())).status, "proposal");
  await rejected(s, request("overflow"), context(), "REQUEST_CAPACITY");
  assert.equal((await s.generateTurn(request("r0"), context())).status, "proposal");
  const gate = defer(); const pending = service(async () => { await gate.promise; throw Error("secret"); });
  const turns = Array.from({ length: 32 }, (_, i) => pending.generateTurn(request(`p${i}`), context()));
  await rejected(pending, request("overflow"), context(), "REQUEST_CAPACITY"); gate.resolve();
  for (const result of await Promise.all(turns)) assert.equal(result.code, "PROVIDER_UNAVAILABLE");
  assert.equal((await pending.generateTurn(request("overflow"), context())).status, "unavailable");
});

test("failed provider response is sanitized, uncached and explicitly retryable", async () => {
  let calls = 0; const s = service(async () => { if (++calls === 1) throw Error("provider credential secret"); return output(); });
  assert.deepEqual(await s.generateTurn(request(), context()), { status: "unavailable", code: "PROVIDER_UNAVAILABLE" });
  assert.equal((await s.generateTurn(request(), context())).status, "proposal"); assert.equal(calls, 2);
});

test("timeout aborts, ignores late output and does not overwrite a retried result", async () => {
  const late = defer(); let calls = 0; let signal;
  const s = service(async (input) => { signal = input.signal; if (++calls === 1) return late.promise; return output(); }, { timeoutMs: 5 });
  assert.deepEqual(await s.generateTurn(request(), context()), { status: "unavailable", code: "PROVIDER_TIMEOUT" });
  assert.equal(signal.aborted, true);
  assert.equal((await s.generateTurn(request(), context())).status, "proposal");
  late.resolve({ ...output(), suggestions: [] }); await Promise.resolve(); await Promise.resolve();
  assert.equal((await s.generateTurn(request(), context())).suggestions.length, 1); assert.equal(calls, 2);
});

test("owner/revision or confirmation changed while provider waits rejects completion", async () => {
  for (const mutate of [
    (c) => { c.ownerID = "owner-B"; }, (c) => { c.currentRevision = "revision-2"; },
    (c) => { c.fields["ingredients[0].amount"].user_confirmed = true; },
  ]) {
    const gate = defer(); const c = context(); const s = service(async () => { await gate.promise; return output(); });
    const result = s.generateTurn(request(), c); await Promise.resolve(); mutate(c); gate.resolve();
    assert.equal((await result).code, "STALE_REVISION");
  }
});

test("private cyclic/BigInt context is neither forwarded nor fingerprinted", async () => {
  const c = context(); c.source.self = c.source; c.source.opaque = 1n; c.fields.notes.raw_value = 2n;
  let seen; const s = service(async (input) => { seen = input; return output(); });
  assert.equal((await s.generateTurn(request(), c)).status, "proposal");
  assert.equal(JSON.stringify(seen).includes("opaque"), false);
});

test("malformed cyclic or BigInt provider output is rejected, not an availability error", async () => {
  const cyclic = output(); cyclic.suggestions[0].raw_value = cyclic;
  const bigint = output(); bigint.suggestions[0].raw_value = 1n;
  for (const o of [cyclic, bigint]) await rejected(service(async () => o), undefined, undefined, "INVALID_PROVIDER_OUTPUT");
});

test("mutable request lineage, review/evidence and field reference changes cannot affect an in-flight result", async () => {
  const mutations = [
    (r) => { r.requestID = "other"; },
    (_r, c) => { c.reviewFields = ["steps"]; },
    (_r, c) => { c.evidence[0].excerpt = "changed"; },
    (_r, c) => { c.fields["ingredients[0].amount"].evidence_ids.push("missing"); },
  ];
  for (const mutate of mutations) {
    const gate = defer(); const c = context(); const r = request(); let seen;
    const s = service(async (input) => { seen = input; await gate.promise; return output(); });
    const pending = s.generateTurn(r, c); await Promise.resolve(); mutate(r, c); gate.resolve();
    assert.equal((await pending).code, "STALE_REVISION");
    assert.deepEqual(seen.fields["ingredients[0].amount"].evidence_ids, ["e1"]);
  }
});

test("combined valid-shape provider values still obey the UTF8 output budget", async () => {
  const c = context(); c.fields = {}; c.reviewFields = ["ingredients"];
  c.evidence = [{ id: "e1", excerpt: "界".repeat(1000) }];
  const o = { questions: [], suggestions: [], usage: { totalTokens: 0 } };
  for (let i = 0; i < 12; i++) {
    const path = `ingredients[${i}].amount`; c.fields[path] = { user_confirmed: false };
    o.suggestions.push({ path, raw_value: "界".repeat(1000), reason: "Original source", evidence_ids: ["e1"] });
  }
  await rejected(service(async () => o), request(), c, "INVALID_PROVIDER_OUTPUT");
});

test("group questions, missing exact paths and maximum supported indices retain source evidence", async () => {
  const c = context(); c.fields = {}; c.reviewFields = ["ingredients", "steps[99].instruction", "title"];
  const o = { questions: [
    { path: "ingredients", question: "Which source ingredients need review?", evidence_ids: ["e1"] },
    { path: "steps[99].instruction", question: "What does this source step mean?", evidence_ids: ["e1"] },
    { path: "title", question: "Which source phrase should be the title?", evidence_ids: ["e1"] },
  ], suggestions: [], usage: { totalTokens: 0 } };
  assert.equal((await service(async () => o).generateTurn(request(), c)).questions.length, 3);
  o.questions[1].path = "steps[100].instruction";
  await rejected(service(async () => o), request(), c, "INVALID_PROVIDER_OUTPUT");
});

test("each concurrent replay caller revalidates its own independently mutable snapshot", async () => {
  for (const mutate of [
    (_r, c) => { c.fields["ingredients[0].amount"].user_confirmed = true; },
    (_r, c) => { c.currentRevision = "revision-2"; },
    (_r, c) => { c.reviewFields = ["steps"]; },
    (_r, c) => { c.evidence[0].excerpt = "changed"; },
    (r) => { r.requestID = "other"; },
  ]) {
    const gate = defer(); let calls = 0; const s = service(async () => { calls++; await gate.promise; return output(); });
    const first = s.generateTurn(request(), context()); const r = request(); const c = context();
    const second = s.generateTurn(r, c); await Promise.resolve(); mutate(r, c); gate.resolve();
    assert.equal((await first).status, "proposal"); assert.equal((await second).code, "STALE_REVISION"); assert.equal(calls, 1);
  }
});

test("status accepts only literal values without invoking object coercion", async () => {
  let calls = 0; let coerced = 0; const s = service(async () => { calls++; return output(); });
  for (const status of [{ toString() { coerced++; return "ready"; } }, { toString() { throw Error("must not run"); } }, 1, true, null]) {
    await rejected(s, request(), { ...context(), status }, "INVALID_INPUT");
  }
  assert.equal(calls, 0); assert.equal(coerced, 0);
});
