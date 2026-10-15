// Developer: gengyun
// Purpose: Exercise the strict edit output validator and the bounded provider factory with fake transport.

import test from "node:test";
import assert from "node:assert/strict";
import { createRecipeEditProvider, validEditOutput } from "./provider.ts";
import { validEditChanges, validEditPath } from "./editSchema.ts";

const id = (n) =>
  `${n.toString(16).padStart(8, "0")}-0000-4000-8000-000000000000`;
const ingredient = id(1);
const step = id(2);

const change = (overrides = {}) => ({
  path: `ingredient:${ingredient}:name`,
  original: "sugar",
  proposed: "honey",
  reason: "1:1 sweetness substitute",
  warnings: [],
  ...overrides,
});

const output = (overrides = {}) => ({
  needsManualEdit: false,
  changes: [change()],
  reasons: [],
  warnings: [],
  ...overrides,
});

test("validEditPath accepts only the three whitelist path kinds", () => {
  assert.equal(validEditPath(`ingredient:${ingredient}:name`), true);
  assert.equal(validEditPath(`ingredient:${ingredient}:amount`), true);
  assert.equal(validEditPath(`step:${step}:instruction`), true);
  assert.equal(validEditPath("title"), false);
  assert.equal(validEditPath("servings"), false);
  assert.equal(validEditPath(`step:${step}:timer`), false);
  assert.equal(validEditPath(`ingredient:${ingredient}:unit`), false);
});

test("validEditChanges rejects empty, duplicate and no-op change sets", () => {
  assert.equal(validEditChanges([change()]), true);
  assert.equal(validEditChanges([]), false);
  assert.equal(validEditChanges([change(), change()]), false);
  assert.equal(
    validEditChanges([change({ proposed: "sugar" })]),
    false,
  );
  assert.equal(
    validEditChanges([change({ original: "" })]),
    false,
  );
});

test("validEditChanges bounds text lengths and rejects overlong steps", () => {
  assert.equal(
    validEditChanges([
      change({ path: `step:${step}:instruction`, proposed: "x".repeat(8001) }),
    ]),
    false,
  );
  assert.equal(
    validEditChanges([change({ proposed: "y".repeat(241) })]),
    false,
  );
});

test("validEditOutput rejects needs_manual_edit with non-empty changes", () => {
  assert.equal(validEditOutput(output()), true);
  assert.equal(
    validEditOutput({
      needsManualEdit: true,
      changes: [],
      reasons: ["no expressible edit"],
      warnings: [],
    }),
    true,
  );
  assert.equal(
    validEditOutput({
      needsManualEdit: true,
      changes: [change()],
      reasons: [],
      warnings: [],
    }),
    false,
  );
  assert.equal(
    validEditOutput({
      needsManualEdit: false,
      changes: "bad",
      reasons: [],
      warnings: [],
    }),
    false,
  );
});

const config = () => ({
  enabled: true,
  route: {
    route_key: "recipe_edit_v1",
    primary_model_id: "model-1",
    enabled: true,
    timeout_ms: 60000,
    max_retries: 1,
    max_output_tokens: 1000,
    temperature: 0.2,
  },
  model: {
    id: "model-1",
    provider_id: "provider-1",
    upstream_model_id: "fixture-model",
    enabled: true,
  },
  provider: {
    id: "provider-1",
    name: "Fixture",
    base_url: "https://example.invalid/v1/",
    secret_ref: "fixture-secret",
    enabled: true,
  },
});

const input = () => ({
  intent: "substitute",
  recipe: {
    id: id(3),
    ingredients: [{ id: ingredient, name: "sugar", amount: "2 tbsp" }],
    steps: [{ id: step, instruction: "Add sugar and stir." }],
  },
  supplement: "less sweet",
  signal: new AbortController().signal,
});

const envelope = (content) => ({
  choices: [{
    message: { role: "assistant", content: JSON.stringify(content) },
  }],
});

const fixture = (overrides = {}) => {
  let transports = 0;
  let captured;
  const options = {
    ...config(),
    resolveSecret: async (ref) => {
      assert.equal(ref, "fixture-secret");
      return "fake-test-key";
    },
    transport: async (request, policy) => {
      transports++;
      captured = { request, policy };
      return new Response(JSON.stringify(envelope(output())), {
        headers: { "Content-Type": "application/json" },
      });
    },
    ...overrides,
  };
  return {
    provider: createRecipeEditProvider(options),
    counts: () => transports,
    captured: () => captured,
  };
};

test("provider builds a bounded OpenAI request and parses validated output", async () => {
  const f = fixture();
  const result = await f.provider(input());
  assert.equal(result.needsManualEdit, false);
  assert.equal(result.changes.length, 1);
  assert.equal(f.counts(), 1);
  const { request } = f.captured();
  assert.equal(request.url, "https://example.invalid/v1/chat/completions");
  assert.equal(request.headers.get("Authorization"), "Bearer fake-test-key");
  const body = JSON.parse(await request.text());
  assert.equal(body.model, "fixture-model");
  assert.equal(body.response_format.type, "json_object");
});

test("provider fails closed when disabled", async () => {
  const provider = createRecipeEditProvider({ ...config(), enabled: false });
  await assert.rejects(provider(input()), {
    message: "EDIT_PROVIDER_DISABLED",
  });
});

test("provider rejects a malformed model output outside the whitelist", async () => {
  const provider = createRecipeEditProvider({
    ...config(),
    resolveSecret: async () => "fake-test-key",
    transport: async () =>
      new Response(
        JSON.stringify(
          envelope(output({ changes: [change({ path: "title" })] })),
        ),
        {
          headers: { "Content-Type": "application/json" },
        },
      ),
  });
  await assert.rejects(provider(input()), { message: "EDIT_PROVIDER_OUTPUT" });
});

test("provider returns needs_manual_edit with empty changes", async () => {
  const provider = createRecipeEditProvider({
    ...config(),
    resolveSecret: async () => "fake-test-key",
    transport: async () =>
      new Response(
        JSON.stringify(envelope({
          needsManualEdit: true,
          changes: [],
          reasons: ["Cannot express ingredient removal within the three kinds"],
          warnings: [],
        })),
        { headers: { "Content-Type": "application/json" } },
      ),
  });
  const result = await provider(input());
  assert.equal(result.needsManualEdit, true);
  assert.equal(result.changes.length, 0);
});
