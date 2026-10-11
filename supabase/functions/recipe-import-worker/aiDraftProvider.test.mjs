// Developer: gengyun
// Purpose: Exercise original offline OpenAI wire fixtures and integration with the validated draft service.

import assert from "node:assert/strict";
import test from "node:test";
import { createOpenAIDraftProvider } from "./aiDraftProvider.ts";
import { createAIDraftTurnService } from "./aiDraftTurn.ts";

const config = () => ({
  enabled: true,
  route: { route_key: "fixture-route", primary_model_id: "model-1", enabled: true, timeout_ms: 60000,
    max_retries: 1, max_output_tokens: 1000, temperature: 0.2 },
  model: { id: "model-1", provider_id: "provider-1", upstream_model_id: "fixture-model", display_name: "Fixture",
    enabled: true, created_at: "2026-01-01T00:00:00Z" },
  provider: { id: "provider-1", name: "Fixture", base_url: "https://example.invalid/v1/", secret_ref: "fixture-secret",
    enabled: true, updated_at: "2026-01-01T00:00:00Z" },
});
const input = (signal = new AbortController().signal) => ({
  fields: { "ingredients[0].amount": { raw_value: null, evidence_ids: ["e1"] } },
  evidence: [{ id: "e1", excerpt: "Use salt to taste." }], reviewFields: ["ingredients"],
  message: "Keep source wording", maxTotalTokens: 4096, signal,
});
const content = () => ({ questions: [], suggestions: [{ path: "ingredients[0].amount", raw_value: "salt to taste",
  evidence_ids: ["e1"], reason: "Original text; exact amount unknown." }] });
const envelope = () => ({ choices: [{ finish_reason: "stop", message: { role: "assistant", content: JSON.stringify(content()) } }],
  usage: { total_tokens: 30, prompt_tokens: 20, completion_tokens: 10 } });
const response = (value = envelope(), options = {}) => new Response(JSON.stringify(value), { headers: { "Content-Type": "application/json; charset=utf-8" }, ...options });
const fixture = (overrides = {}) => {
  let secrets = 0; let transports = 0; let captured;
  const options = { ...config(), resolveSecret: async (ref) => { secrets++; assert.equal(ref, "fixture-secret"); return "fake-test-key"; },
    transport: async (request, policy) => { transports++; captured = { request, policy }; return response(); }, ...overrides };
  return { options, provider: createOpenAIDraftProvider(options), counts: () => ({ secrets, transports }), captured: () => captured };
};
const rejects = (operation, code) => assert.rejects(operation, { message: code });
const defer = () => { let resolve; const promise = new Promise((r) => { resolve = r; }); return { promise, resolve }; };

test("existing row configuration produces exact bounded OpenAI request and trusted usage mapping", async () => {
  const f = fixture(); const i = input(); i.owner = "private extra field";
  const result = await f.provider(i);
  const { request, policy } = f.captured();
  assert.equal(request.url, "https://example.invalid/v1/chat/completions");
  assert.equal(request.method, "POST"); assert.equal(request.redirect, "error");
  assert.equal(request.headers.get("authorization"), "Bearer fake-test-key");
  assert.equal(request.headers.get("content-type"), "application/json");
  assert.equal(policy.signal, i.signal); assert.equal(policy.maxResponseBytes, 65536);
  const body = await request.json();
  assert.equal(body.model, "fixture-model"); assert.equal(body.max_tokens, 1000); assert.equal(body.stream, false);
  assert.equal(body.temperature, 0.2); assert.deepEqual(body.response_format, { type: "json_object" });
  assert.equal(body.messages[0].role, "system"); assert.equal(body.messages[1].role, "user");
  assert.equal(JSON.stringify(body).includes("private extra field"), false);
  assert.equal(JSON.stringify(body).includes("fake-test-key"), false);
  assert.equal(JSON.stringify(result).includes("fake-test-key"), false);
  assert.deepEqual(result, { ...content(), usage: { totalTokens: 30 } });
  assert.deepEqual(f.counts(), { secrets: 1, transports: 1 });
});

test("disabled, inactive, mismatched or malformed existing configuration fails before dependencies", async () => {
  const mutations = [
    (o) => { delete o.enabled; }, (o) => { o.enabled = "true"; },
    (o) => { o.route.enabled = false; }, (o) => { o.model.enabled = false; }, (o) => { o.provider.enabled = false; },
    (o) => { o.route.primary_model_id = "other"; }, (o) => { o.model.provider_id = "other"; },
    (o) => { o.provider.base_url = "http://example.invalid/v1"; },
    (o) => { o.provider.base_url = "https://u:p@example.invalid/v1"; },
    (o) => { o.provider.base_url = "https://example.invalid/v1?key=bad"; },
    (o) => { o.provider.base_url = "https://example.invalid/v1#fragment"; },
    (o) => { o.model.upstream_model_id = ""; }, (o) => { o.provider.name = ""; },
    (o) => { o.provider.secret_ref = null; }, (o) => { o.route.timeout_ms = 999; },
    (o) => { o.route.max_retries = 4; }, (o) => { o.route.max_output_tokens = 4097; },
    (o) => { o.route.temperature = NaN; }, (o) => { o.route.temperature = 2.1; },
    (o) => { o.resolveSecret = undefined; }, (o) => { o.transport = undefined; },
  ];
  for (const mutate of mutations) {
    const f = fixture(); mutate(f.options); const provider = createOpenAIDraftProvider(f.options);
    await rejects(() => provider(input()), "DRAFT_PROVIDER_DISABLED"); assert.deepEqual(f.counts(), { secrets: 0, transports: 0 });
  }
});

test("factory captures route and dependencies without accepting caller config overrides", async () => {
  const f = fixture(); f.options.provider.base_url = "https://attacker.invalid";
  f.options.model.upstream_model_id = "attacker"; f.options.provider.secret_ref = "attacker-secret";
  f.options.transport = async () => { throw Error("wrong transport"); };
  await f.provider({ ...input(), apiKey: "attacker", baseUrl: "https://attacker.invalid", model: "attacker" });
  const { request } = f.captured(); const body = await request.json();
  assert.equal(request.url, "https://example.invalid/v1/chat/completions"); assert.equal(body.model, "fixture-model");
  assert.equal(JSON.stringify(body).includes("attacker"), false);
});

test("null temperature and boundary max output tokens use existing route settings", async () => {
  const f = fixture(); f.options.route.temperature = null; f.options.route.max_output_tokens = 4096;
  await createOpenAIDraftProvider(f.options)(input()); const body = await f.captured().request.json();
  assert.equal("temperature" in body, false); assert.equal(body.max_tokens, 4096);
});

test("input budget and malformed payload stop before secret resolution", async () => {
  const f = fixture();
  for (const i of [{ ...input(), maxTotalTokens: 5000 }, { ...input(), signal: null }, { ...input(), fields: null }]) {
    await rejects(() => f.provider(i), "DRAFT_PROVIDER_INPUT");
  }
  const oversized = input(); oversized.message = "界".repeat(12000);
  await rejects(() => f.provider(oversized), "DRAFT_PROVIDER_INPUT_BUDGET");
  const circular = input(); circular.fields.self = circular.fields;
  await rejects(() => f.provider(circular), "DRAFT_PROVIDER_INPUT_BUDGET");
  assert.deepEqual(f.counts(), { secrets: 0, transports: 0 });
});

test("fake key rejection and dependency exceptions never leak secrets or issue transport", async () => {
  for (const key of ["", "x".repeat(8193), "secret\r\ninjected: header", null]) {
    let transports = 0;
    const f = fixture({ resolveSecret: async () => key, transport: async () => { transports++; return response(); } });
    await rejects(() => f.provider(input()), "DRAFT_PROVIDER_UNAVAILABLE"); assert.equal(transports, 0);
  }
  const f = fixture({ resolveSecret: async () => { throw Error("actual private credential"); } });
  await rejects(() => f.provider(input()), "DRAFT_PROVIDER_UNAVAILABLE");
  const transportError = fixture({ transport: async () => { throw Error("private upstream body"); } });
  await rejects(() => transportError.provider(input()), "DRAFT_PROVIDER_UNAVAILABLE");
});

test("pre-abort and abort during pending or late secret resolution never issue transport", async () => {
  const early = new AbortController(); early.abort(); const f = fixture();
  await rejects(() => f.provider(input(early.signal)), "DRAFT_PROVIDER_ABORTED"); assert.deepEqual(f.counts(), { secrets: 0, transports: 0 });
  const late = defer(); const started = defer(); let transports = 0;
  const waiting = fixture({ resolveSecret: async () => { started.resolve(); return late.promise; }, transport: async () => { transports++; return response(); } });
  const controller = new AbortController(); const pending = waiting.provider(input(controller.signal));
  await started.promise; controller.abort(); await rejects(() => pending, "DRAFT_PROVIDER_ABORTED");
  late.resolve("fake-test-key"); await Promise.resolve(); await Promise.resolve(); assert.equal(transports, 0);
});

test("abort during pending transport settles and cancels a late response body", async () => {
  const late = defer(); const started = defer(); const canceled = defer();
  const f = fixture({ transport: async () => { started.resolve(); return late.promise; } });
  const controller = new AbortController(); const pending = f.provider(input(controller.signal));
  await started.promise; controller.abort(); await rejects(() => pending, "DRAFT_PROVIDER_ABORTED");
  late.resolve(new Response(new ReadableStream({ cancel() { canceled.resolve(); } }), { headers: { "content-type": "application/json" } }));
  await canceled.promise;
});

test("abort cancels a permanently pending stream read without waiting for a chunk", async () => {
  const reading = defer(); let canceled = false;
  const stream = new ReadableStream({ pull() { reading.resolve(); }, cancel() { canceled = true; } }, { highWaterMark: 0 });
  const f = fixture({ transport: async () => new Response(stream, { headers: { "content-type": "application/json" } }) });
  const controller = new AbortController(); const pending = f.provider(input(controller.signal));
  await reading.promise; controller.abort(); await rejects(() => pending, "DRAFT_PROVIDER_ABORTED"); assert.equal(canceled, true);
});

test("HTTP redirects, errors, MIME, invalid JSON and UTF8 responses fail closed", async () => {
  const redirected = response(); Object.defineProperty(redirected, "redirected", { value: true });
  const bad = [redirected, response({}, { status: 307 }), response({ secret: "upstream" }, { status: 503 }),
    new Response("{}", { headers: { "content-type": "text/event-stream" } }),
    new Response("broken", { headers: { "content-type": "application/json" } }),
    new Response(Uint8Array.of(0xc3, 0x28), { headers: { "content-type": "application/json" } }),
  ];
  for (const r of bad) await rejects(() => fixture({ transport: async () => r }).provider(input()), "DRAFT_PROVIDER_RESPONSE");
});

test("declared and chunked actual response size are independently bounded and canceled", async () => {
  let canceled = 0;
  for (const header of ["65537", "invalid", null]) {
    const stream = new ReadableStream({ start(c) { if (header === null) c.enqueue(new Uint8Array(65537)); }, cancel() { canceled++; } });
    const headers = { "content-type": "application/json", ...(header === null ? {} : { "content-length": header }) };
    await rejects(() => fixture({ transport: async () => new Response(stream, { headers }) }).provider(input()), "DRAFT_PROVIDER_RESPONSE");
  }
  assert.equal(canceled, 3);
});

test("choices, finish reasons, toolcalls, refusals and token accounting require exact trusted envelope", async () => {
  const mutate = [
    (o) => { o.choices = []; }, (o) => { o.choices.push(o.choices[0]); },
    (o) => { o.choices[0].finish_reason = "length"; }, (o) => { o.choices[0].finish_reason = "content_filter"; },
    (o) => { o.choices[0].message.role = "user"; }, (o) => { o.choices[0].message.tool_calls = []; },
    (o) => { o.choices[0].message.function_call = {}; }, (o) => { o.choices[0].message.refusal = null; },
    (o) => { o.choices[0].message.content = "badJSON"; }, (o) => { o.choices[0].message.content = "x".repeat(32769); },
    (o) => { o.choices[0].message.content = JSON.stringify({ ...content(), usage: { totalTokens: 0 } }); },
    (o) => { o.usage.total_tokens = 4097; }, (o) => { o.usage.total_tokens = -1; },
    (o) => { o.usage.total_tokens = "30"; }, (o) => { o.usage.total_tokens = 1.5; },
    (o) => { o.usage.completion_tokens = 11; }, (o) => { delete o.usage.prompt_tokens; },
    (o) => { delete o.usage; },
  ];
  for (const m of mutate) { const o = envelope(); m(o); await rejects(() => fixture({ transport: async () => response(o) }).provider(input()), "DRAFT_PROVIDER_RESPONSE"); }
});

test("integrated actual draft service applies evidence/confirmed policy rather than trusting model JSON", async () => {
  const context = { ownerID: "owner-A", currentRevision: "revision-1", status: "needs_review", fields: {
    "ingredients[0].amount": { raw_value: null, user_confirmed: false, evidence_ids: ["e1"] },
    "ingredients[1].amount": { raw_value: "a little", user_confirmed: true, evidence_ids: ["e1"] },
  }, evidence: [{ id: "e1", excerpt: "Use salt to taste." }], reviewFields: ["ingredients"] };
  const request = { ownerID: "owner-A", expectedRevision: "revision-1", requestID: "r1", message: "Keep source wording" };
  const f = fixture(); const s = createAIDraftTurnService({ enabled: true, provider: f.provider });
  const result = await s.generateTurn(request, context);
  assert.equal(result.status, "proposal"); assert.equal(result.requiresApproval, true); assert.equal(result.origin, "AI_suggested");
  const o = envelope(); const parsed = content(); parsed.suggestions[0].path = "ingredients[1].amount"; o.choices[0].message.content = JSON.stringify(parsed);
  const protectedService = createAIDraftTurnService({ enabled: true, provider: fixture({ transport: async () => response(o) }).provider });
  assert.equal((await protectedService.generateTurn(request, context)).code, "INVALID_PROVIDER_OUTPUT");
});

test("integrated service safely degrades when provider token usage exceeds the total budget", async () => {
  const o = envelope(); o.usage.total_tokens = 4097;
  const f = fixture({ transport: async () => response(o) });
  const s = createAIDraftTurnService({ enabled: true, provider: f.provider });
  const context = { ownerID: "owner-A", currentRevision: "revision-1", status: "needs_review",
    fields: { "ingredients[0].amount": { raw_value: null, user_confirmed: false, evidence_ids: ["e1"] } },
    evidence: [{ id: "e1", excerpt: "Use salt to taste." }], reviewFields: ["ingredients"] };
  const r = { ownerID: "owner-A", expectedRevision: "revision-1", requestID: "r1", message: "Keep source wording" };
  const before = JSON.stringify(context);
  assert.deepEqual(await s.generateTurn(r, context), { status: "unavailable", code: "PROVIDER_UNAVAILABLE" });
  assert.equal(JSON.stringify(context), before);
});
