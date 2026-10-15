// Developer: gengyun
// Purpose: Main-path coverage for the recipe-translations handler contract.

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { handleRequest, type TranslationDependencies } from "./handler.ts";
import type { TranslationProvider } from "./provider.ts";

const OWNER = "00000000-0000-4000-8000-000000000001";
const INGREDIENT = "00000000-0000-4000-8000-000000000002";
const STEP = "00000000-0000-4000-8000-000000000003";

function dependencies(provider: TranslationProvider | null = null): TranslationDependencies {
  return {
    verifiedOwner: async () => ({ id: OWNER }),
    provider,
  };
}

function anonymous(provider: TranslationProvider | null = null): TranslationDependencies {
  return {
    verifiedOwner: async () => null,
    provider,
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
    ...overrides,
  };
  return new Request("https://example.com/recipe-translations", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("returns a reviewable proposal for a valid translation", async () => {
  const provider: TranslationProvider = async () => ({
    title: "番茄汤",
    summary: "一碗温暖的汤。",
    ingredient_names: [{ id: INGREDIENT, translated: "番茄" }],
    ingredient_amounts: [{ id: INGREDIENT, translated: "适量" }],
    step_instructions: [{ id: STEP, translated: "加热30分钟。" }],
    step_titles: [{ id: STEP, translated: "烹饪" }],
  });
  const response = await handleRequest(request(), dependencies(provider));
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

Deno.test("rejects an unsupported target locale", async () => {
  const response = await handleRequest(request({ target_locale: "de" }), dependencies());
  assertEquals(response.status, 400);
});

Deno.test("rejects provider output that fabricates a number in a vague amount", async () => {
  const provider: TranslationProvider = async () => ({
    ingredient_amounts: [{ id: INGREDIENT, translated: "1 tsp" }],
  });
  const response = await handleRequest(request(), dependencies(provider));
  assertEquals(response.status, 502);
});

Deno.test("rejects provider output that changes step numbers", async () => {
  const provider: TranslationProvider = async () => ({
    step_instructions: [{ id: STEP, translated: "加热45分钟。" }],
  });
  const response = await handleRequest(request(), dependencies(provider));
  assertEquals(response.status, 502);
});

Deno.test("rejects an anonymous request", async () => {
  const response = await handleRequest(request(), anonymous());
  assertEquals(response.status, 401);
});

Deno.test("accepts a partial translation that omits ingredient and step fields", async () => {
  const provider: TranslationProvider = async () => ({
    title: "番茄汤",
    summary: "一碗温暖的汤。",
  });
  const response = await handleRequest(request(), dependencies(provider));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.title, "番茄汤");
  assertEquals(body.ingredient_names.length, 0);
  assertEquals(body.step_instructions.length, 0);
});
