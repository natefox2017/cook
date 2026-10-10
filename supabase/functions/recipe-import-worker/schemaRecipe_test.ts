// Developer: gengyun
// Purpose: Verify conservative Schema.org Recipe JSON-LD extraction and review outcomes.

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { parseSchemaOrgRecipePage } from "./schemaRecipe.ts";

const fixture = async (name: string): Promise<string> =>
  await Deno.readTextFile(new URL(`./fixtures/${name}`, import.meta.url));

const source = {
  originalURL: "https://recipes.example/shared",
  canonicalURL: "https://recipes.example/canonical",
  platformHint: "example",
};

Deno.test("extracts only explicit Schema.org Recipe fields from @graph", async () => {
  const result = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174000",
    html: await fixture("complete-recipe.html"),
    source,
  });

  assertEquals(result.status, "ready");
  assertEquals(result.fields.title.raw_value, "Weeknight soup");
  assertEquals(
    result.fields["ingredients[1].raw_text"].raw_value,
    "salt to taste",
  );
  assertEquals(result.fields["ingredients[1].amount"].normalized_value, null);
  assertEquals(
    result.fields["steps[1].instruction"].raw_value,
    "Add salt to taste.",
  );
  assertEquals(result.source.original_url, source.originalURL);
  assertEquals(result.source.canonical_url, source.canonicalURL);
  assertEquals(result.source.platform, "example");
  assertEquals(result.source.author_name, "Mina Cook");
  assertEquals(result.source.source_title, "Original page title");
  assertEquals(result.evidence[0].source_type, "webpage_structured_data");
  assertStringIncludes(String(result.evidence[0].excerpt), "Weeknight soup");
});

Deno.test("keeps missing fields and exposes review paths", async () => {
  const result = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174001",
    html: await fixture("incomplete-recipe.html"),
    source,
  });

  assertEquals(result.status, "needs_review");
  assertEquals(result.review_fields, ["ingredients", "steps"]);
  assertEquals(result.fields.title.raw_value, "Name only recipe");
});

Deno.test("does not choose between multiple Recipe entities", async () => {
  const result = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174002",
    html: await fixture("multiple-recipes.html"),
    source,
  });

  assertEquals(result.status, "needs_review");
  assertEquals(result.fields, {});
  assertEquals(result.review_fields, [
    "recipe_selection",
    "title",
    "ingredients",
    "steps",
  ]);
  assertEquals(result.candidate_recipes?.length, 2);
  assertEquals(result.candidate_recipes?.map((c) => c.title), [
    "First recipe", "Second recipe",
  ]);
  assertEquals(result.candidate_recipes?.every((c) => c.evidence_ids.length === 1), true);
  const repeated = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174002",
    html: await fixture("multiple-recipes.html"),
    source,
  });
  assertEquals(
    repeated.candidate_recipes?.map((c) => c.candidate_id),
    result.candidate_recipes?.map((c) => c.candidate_id),
  );
  assertStringIncludes(
    String(result.evidence[0].excerpt),
    "First recipe; Second recipe",
  );
});

Deno.test("reports malformed JSON-LD instead of inventing recipe fields", async () => {
  const result = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174003",
    html: await fixture("malformed-recipe-jsonld.html"),
    source,
  });

  assertEquals(result.status, "needs_review");
  assertEquals(result.fields, {});
  assertEquals(result.review_fields, [
    "title",
    "ingredients",
    "steps",
    "structured_data",
  ]);
});

Deno.test("keeps structured ingredients and steps separated by candidate", () => {
  const html = `<html><script type="application/ld+json">{
    "@context":"https://schema.org","@graph":[
      {"@type":"Recipe","name":"Pasta","recipeIngredient":["100g pasta"],
       "recipeInstructions":[{"@type":"HowToStep","text":"Boil pasta"}]},
      {"@type":"Recipe","name":"Soup","recipeIngredient":["200ml stock"],
       "recipeInstructions":[{"@type":"HowToStep","text":"Simmer stock"}]}
    ]}</script></html>`;
  const result = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174002", html, source
  });
  assertEquals(result.fields, {});
  assertEquals(result.candidate_recipes?.[0].ingredients, ["100g pasta"]);
  assertEquals(result.candidate_recipes?.[1].ingredients, ["200ml stock"]);
  assertEquals(result.candidate_recipes?.[0].steps, ["Boil pasta"]);
  assertEquals(result.candidate_recipes?.[1].steps, ["Simmer stock"]);
});


// The parent import may be re-run after a website rearranges its JSON-LD graph.
// An unrelated first recipe must not change the IDs used by private child saves.
Deno.test("multi-recipe IDs survive source reordering and unrelated insertion", () => {
  const soup = {
    "@type": "Recipe", name: "Soup",
    recipeIngredient: ["200 ml stock"],
    recipeInstructions: [{ "@type": "HowToStep", text: "Simmer stock." }],
  };
  const pasta = {
    "@type": "Recipe", name: "Pasta",
    recipeIngredient: ["100 g pasta"],
    recipeInstructions: [{ "@type": "HowToStep", text: "Boil pasta." }],
  };
  const pie = {
    "@type": "Recipe", name: "Pie",
    recipeIngredient: ["1 apple"],
    recipeInstructions: [{ "@type": "HowToStep", text: "Bake pie." }],
  };
  const resultFor = (recipes: object[]) =>
    parseSchemaOrgRecipePage({
      id: "123e4567-e89b-12d3-a456-426614174002",
      html: '<html><script type="application/ld+json">' +
        JSON.stringify({ "@context": "https://schema.org", "@graph": recipes }) +
        '</script></html>',
      source,
    });
  const initial = resultFor([soup, pasta]).candidate_recipes ?? [];
  const reordered = resultFor([pasta, soup]).candidate_recipes ?? [];
  const inserted = resultFor([pie, soup, pasta]).candidate_recipes ?? [];
  assertEquals(initial.map((candidate) => candidate.candidate_id), [
    reordered[1].candidate_id,
    reordered[0].candidate_id,
  ]);
  assertEquals(initial.map((candidate) => candidate.candidate_id),
    inserted.slice(1).map((candidate) => candidate.candidate_id));
  assertEquals(initial.every((candidate) =>
    /^candidate-v2-[a-f0-9]{32}$/.test(candidate.candidate_id)), true);
  assertEquals(resultFor([soup, soup]).candidate_recipes?.map((candidate) =>
    candidate.candidate_id).length, 2);
  const duplicates = resultFor([soup, soup]).candidate_recipes ?? [];
  assertEquals(duplicates[1].candidate_id, duplicates[0].candidate_id + "-2");
  assertEquals(new Set(duplicates.map((candidate) => candidate.candidate_id)).size, 2);
});

Deno.test("caps preview at eight recipes and reports additional candidates", () => {
  const recipes = Array.from({ length: 9 }, (_, index) => ({
    "@type": "Recipe",
    name: `Dish ${index + 1}`,
    recipeIngredient: [`${index + 1} g ingredient ${index + 1}`],
    recipeInstructions: [{
      "@type": "HowToStep",
      text: `Prepare dish ${index + 1}.`,
    }],
  }));
  const result = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174004",
    html: `<html><script type="application/ld+json">${JSON.stringify({
      "@context": "https://schema.org", "@graph": recipes,
    })}</script></html>`,
    source,
  });

  assertEquals(result.status, "needs_review");
  assertEquals(result.fields, {});
  assertEquals(result.candidate_recipes?.length, 8);
  assertEquals(result.candidate_recipes?.map((candidate) => candidate.title), [
    "Dish 1", "Dish 2", "Dish 3", "Dish 4",
    "Dish 5", "Dish 6", "Dish 7", "Dish 8",
  ]);
  assertEquals(result.review_fields.includes("recipe_selection_truncated"), true);
  assertEquals(result.evidence.length, 9); // Parent evidence plus eight candidates.
});

Deno.test("partially populated sibling recipe never borrows another candidate's facts", () => {
  const recipes = [
    {
      "@type": "Recipe",
      name: "Full soup",
      recipeIngredient: ["250 ml broth"],
      recipeInstructions: [{ "@type": "HowToStep", text: "Simmer." }],
    },
    { "@type": "Recipe", name: "Untested draft" },
  ];
  const result = parseSchemaOrgRecipePage({
    id: "123e4567-e89b-12d3-a456-426614174005",
    html: `<script type="application/ld+json">${JSON.stringify({
      "@context": "https://schema.org", "@graph": recipes,
    })}</script>`,
    source,
  });

  assertEquals(result.status, "needs_review");
  assertEquals(result.fields, {});
  assertEquals(result.candidate_recipes?.length, 2);
  assertEquals(result.candidate_recipes?.[0].ingredients, ["250 ml broth"]);
  assertEquals(result.candidate_recipes?.[0].steps, ["Simmer."]);
  assertEquals(result.candidate_recipes?.[0].review_fields, []);
  assertEquals(result.candidate_recipes?.[1].title, "Untested draft");
  assertEquals(result.candidate_recipes?.[1].ingredients, []);
  assertEquals(result.candidate_recipes?.[1].steps, []);
  assertEquals(result.candidate_recipes?.[1].review_fields, ["ingredients", "steps"]);
  assertEquals(
    result.candidate_recipes?.[0].evidence_ids[0] ===
      result.candidate_recipes?.[1].evidence_ids[0],
    false,
  );
});
