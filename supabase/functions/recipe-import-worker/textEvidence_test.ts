// Developer: gengyun
// Purpose: Verifies evidence-first extraction without invented quantities or steps.

import { parseLocalText } from "./textEvidence.ts";

function expect(condition: unknown, message: string): void {
  if (!condition) throw new Error(message);
}

const jobID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

Deno.test("labelled English source retains ambiguous amounts", () => {
  const result = parseLocalText({
    id: jobID,
    source_value: `Vegetable Soup
Ingredients
- Salt to taste
- 1–2 tomatoes
Steps
1. Simmer until tender
2. Serve`,
  });
  expect(result.recipe_id === jobID, "Recipe ID must be deterministic");
  expect(result.status === "ready", "Explicit title, ingredients and steps should be ready");
  expect(result.fields["ingredients[0].amount"].raw_value === "- Salt to taste",
    "Original ingredient phrase was changed");
  expect(result.fields["ingredients[0].amount"].normalized_value === null,
    "Approximate amount must not gain invented numeric normalization");
  expect(result.fields["steps[0].instruction"].raw_value === "Simmer until tender",
    "Step evidence should not gain an invented timer");
  expect(result.review_fields.length === 0, "Complete labelled example was flagged");
});

Deno.test("Chinese input with missing instructions keeps needs_review", () => {
  const result = parseLocalText({
    id: jobID,
    source_value: "番茄汤\n材料\n盐适量\n番茄 2个",
  });
  expect(result.status === "needs_review", "Missing steps were not flagged");
  expect(result.review_fields.includes("steps"), "Missing step review marker absent");
  expect(result.fields["ingredients[0].amount"].normalized_value === null,
    "Uncertain amount must stay nonnumeric");
});

Deno.test("unstructured text is not hallucinated into a full recipe", () => {
  const result = parseLocalText({
    id: jobID,
    source_value: "A post about cooking and seasoning.",
  });
  expect(result.status === "needs_review", "Unstructured text should need review");
  expect(!("steps[0].instruction" in result.fields), "Invented a cooking step");
  expect(!("ingredients[0].amount" in result.fields), "Invented an ingredient");
  expect(result.evidence[0].excerpt === "A post about cooking and seasoning.",
    "Original evidence was discarded");
});

Deno.test("raw source HTML is evidence, never executed", () => {
  const text = "<script>alert('xss')</script>\nIngredients\nSalt to taste";
  const result = parseLocalText({ id: jobID, source_value: text });
  expect(result.status === "needs_review", "Missing cooking steps must need review");
  expect(result.evidence[0].excerpt === text, "Raw source was changed");
});
