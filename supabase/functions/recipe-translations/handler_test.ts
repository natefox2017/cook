// Developer: gengyun
// Purpose: Main-path coverage for the recipe-translations handler contract (adapted to the metered,
//          staged, revision-checked handler interface).

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { handleRequest, type Dependencies } from "./handler.ts";

const OWNER = "00000000-0000-4000-8000-000000000001";
const RECIPE = "00000000-0000-4000-8000-000000000002";
const PROPOSAL = "00000000-0000-4000-8000-000000000003";
const INGREDIENT = "00000000-0000-4000-8000-000000000004";
const STEP = "00000000-0000-4000-8000-000000000005";
const REVISION = "2024-01-01T00:00:00.000Z";

function dependencies(overrides: Partial<Dependencies> = {}): Dependencies {
  return {
    verifiedOwner: async () => ({ id: OWNER, isAnonymous: false }),
    isEnabled: async () => true,
    stage: "commercial",
    loadOwnedRecipe: async () => ({ id: RECIPE, updatedAt: REVISION }),
    loadFinalizedResult: async () => null,
    prepare: async () => ({
      baseUrl: "https://provider.invalid/v1",
      body: "{}",
      key: "test-key",
      timeoutMs: 60_000,
    }),
    dispatch: async () => ({
      title: "番茄汤",
      summary: "一碗温暖的汤。",
      ingredient_names: [{ id: INGREDIENT, translated: "番茄" }],
      ingredient_amounts: [{ id: INGREDIENT, translated: "适量" }],
      step_instructions: [{ id: STEP, translated: "加热30分钟。" }],
      step_titles: [{ id: STEP, translated: "烹饪" }],
    }),
    reserve: async () => ({ code: "RESERVED", reservation: { status: "reserved" } }),
    markDispatched: async () => ({ code: "DISPATCHED" }),
    finalize: async () => ({ code: "FINALIZED" }),
    release: async () => ({ code: "RELEASED" }),
    releaseFailed: async () => ({ code: "RELEASED" }),
    ...overrides,
  };
}

function request(overrides: Record<string, unknown> = {}): Request {
  const body = {
    target_locale: "zh-Hans",
    recipe: {
      title: "Tomato Soup",
      summary: "A warm soup.",
      ingredients: [{ id: INGREDIENT, name: "Tomato", amount_text: "to taste" }],
      steps: [{ id: STEP, title: "Cook", instruction: "Heat for 30 minutes." }],
      source_url: null,
      source_name: null,
    },
    recipe_id: RECIPE,
    expected_revision: REVISION,
    proposal_id: PROPOSAL,
    ...overrides,
  };
  return new Request("https://example.com/recipe-translations", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer test-token",
    },
    body: JSON.stringify(body),
  });
}

Deno.test("returns a reviewable proposal for a valid translation", async () => {
  const response = await handleRequest(request(), dependencies());
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.target_locale, "zh-Hans");
  assertEquals(body.title, "番茄汤");
  assertEquals(body.ingredient_names[0].original, "Tomato");
  assertEquals(body.ingredient_names[0].translated, "番茄");
  assertEquals(body.ingredient_amounts[0].translated, "适量");
  assertEquals(body.step_instructions[0].translated, "加热30分钟。");
  assertEquals(body.source_url, null);
});

Deno.test("rejects provider output that fabricates a number in a vague amount", async () => {
  const deps = dependencies({
    dispatch: async () => ({
      title: "番茄汤",
      summary: "一碗温暖的汤。",
      ingredient_names: [{ id: INGREDIENT, translated: "番茄" }],
      ingredient_amounts: [{ id: INGREDIENT, translated: "1 tsp" }],
      step_instructions: [{ id: STEP, translated: "加热30分钟。" }],
      step_titles: [{ id: STEP, translated: "烹饪" }],
    }),
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
});

Deno.test("rejects provider output that changes step numbers", async () => {
  const deps = dependencies({
    dispatch: async () => ({
      title: "番茄汤",
      summary: "一碗温暖的汤。",
      ingredient_names: [{ id: INGREDIENT, translated: "番茄" }],
      ingredient_amounts: [{ id: INGREDIENT, translated: "适量" }],
      step_instructions: [{ id: STEP, translated: "加热40分钟。" }],
      step_titles: [{ id: STEP, translated: "烹饪" }],
    }),
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
});

Deno.test("rejects an unsupported target locale", async () => {
  const response = await handleRequest(request({ target_locale: "de" }), dependencies());
  assertEquals(response.status, 422);
});

Deno.test("rejects a stale source revision before any provider side effect", async () => {
  const deps = dependencies({
    loadOwnedRecipe: async () => ({ id: RECIPE, updatedAt: "2024-01-02T00:00:00.000Z" }),
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 409);
});

Deno.test("returns UPGRADE_REQUIRED when the owner is not premium", async () => {
  const deps = dependencies({
    reserve: async () => ({ code: "UPGRADE_REQUIRED" }),
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 402);
});

Deno.test("returns QUOTA_EXCEEDED when the monthly quota is exhausted", async () => {
  const deps = dependencies({
    reserve: async () => ({ code: "QUOTA_EXCEEDED", reset_at: "2024-02-01T00:00:00.000Z" }),
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 429);
});

Deno.test("returns the persisted proposal on a committed reservation replay without re-dispatching", async () => {
  const persisted = {
    target_locale: "zh-Hans",
    title: "番茄汤",
    summary: "一碗温暖的汤。",
    ingredient_names: [{ id: INGREDIENT, original: "Tomato", translated: "番茄" }],
    ingredient_amounts: [{ id: INGREDIENT, original: "to taste", translated: "适量" }],
    step_instructions: [{ id: STEP, original: "Heat for 30 minutes.", translated: "加热30分钟。" }],
    step_titles: [{ id: STEP, original: "Cook", translated: "烹饪" }],
    source_url: null,
    source_name: null,
  };
  let markDispatchedCalled = false;
  let dispatchCalled = false;
  const deps = dependencies({
    reserve: async () => ({ code: "REPLAY", reservation: { status: "committed" } }),
    loadFinalizedResult: async () => persisted,
    markDispatched: async () => {
      markDispatchedCalled = true;
      return { code: "DISPATCHED" };
    },
    dispatch: async () => {
      dispatchCalled = true;
      return persisted;
    },
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.title, "番茄汤");
  assertEquals(body.ingredient_names[0].translated, "番茄");
  assertEquals(markDispatchedCalled, false);
  assertEquals(dispatchCalled, false);
});

Deno.test("rejects provider output that drops ingredient names for a non-empty recipe", async () => {
  const deps = dependencies({
    dispatch: async () => ({
      title: "番茄汤",
      summary: "一碗温暖的汤。",
      ingredient_names: [],
      ingredient_amounts: [{ id: INGREDIENT, translated: "适量" }],
      step_instructions: [{ id: STEP, translated: "加热30分钟。" }],
      step_titles: [{ id: STEP, translated: "烹饪" }],
    }),
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
});

Deno.test("rejects provider output that drops step instructions for a non-empty recipe", async () => {
  const deps = dependencies({
    dispatch: async () => ({
      title: "番茄汤",
      summary: "一碗温暖的汤。",
      ingredient_names: [{ id: INGREDIENT, translated: "番茄" }],
      ingredient_amounts: [{ id: INGREDIENT, translated: "适量" }],
      step_instructions: [],
      step_titles: [{ id: STEP, translated: "烹饪" }],
    }),
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
});

Deno.test("releases a still-reserved unit when pre-flight provider checks fail", async () => {
  let released = false;
  let markDispatchedCalled = false;
  let dispatchCalled = false;
  const deps = dependencies({
    prepare: async () => {
      throw new Error("TRANSLATION_PROVIDER_DISABLED");
    },
    release: async () => {
      released = true;
      return { code: "RELEASED" };
    },
    markDispatched: async () => {
      markDispatchedCalled = true;
      return { code: "DISPATCHED" };
    },
    dispatch: async () => {
      dispatchCalled = true;
      return {};
    },
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
  assertEquals(released, true);
  assertEquals(markDispatchedCalled, false);
  assertEquals(dispatchCalled, false);
});

Deno.test("keeps the dispatch fence when the provider transport outcome is ambiguous", async () => {
  let released = false;
  let releaseFailed = false;
  let markDispatchedCalled = false;
  const deps = dependencies({
    dispatch: async () => {
      throw new Error("TRANSLATION_PROVIDER_UNAVAILABLE");
    },
    release: async () => {
      released = true;
      return { code: "RELEASED" };
    },
    releaseFailed: async () => {
      releaseFailed = true;
      return { code: "RELEASED" };
    },
    markDispatched: async () => {
      markDispatchedCalled = true;
      return { code: "DISPATCHED" };
    },
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
  assertEquals(markDispatchedCalled, true);
  assertEquals(released, false);
  assertEquals(releaseFailed, false);
});

Deno.test("releases a known-invalid dispatched provider outcome", async () => {
  let releaseFailed = false;
  const deps = dependencies({
    dispatch: async () => {
      throw new Error("TRANSLATION_PROVIDER_RESPONSE");
    },
    releaseFailed: async () => {
      releaseFailed = true;
      return { code: "RELEASED" };
    },
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
  assertEquals(releaseFailed, true);
});

Deno.test("fails closed on a dispatched_unknown replay without re-dispatching", async () => {
  let prepareCalled = false;
  let markDispatchedCalled = false;
  let dispatchCalled = false;
  const deps = dependencies({
    reserve: async () => ({ code: "REPLAY", reservation: { status: "dispatched_unknown" } }),
    prepare: async () => {
      prepareCalled = true;
      return { baseUrl: "https://provider.invalid/v1", body: "{}", key: "k", timeoutMs: 60_000 };
    },
    markDispatched: async () => {
      markDispatchedCalled = true;
      return { code: "DISPATCHED" };
    },
    dispatch: async () => {
      dispatchCalled = true;
      return {};
    },
  });
  const response = await handleRequest(request(), deps);
  assertEquals(response.status, 503);
  assertEquals(prepareCalled, false);
  assertEquals(markDispatchedCalled, false);
  assertEquals(dispatchCalled, false);
});
