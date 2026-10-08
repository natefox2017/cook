// Developer: gengyun
// Purpose: Extract only evidenced Schema.org Recipe JSON-LD fields from public HTML.

import { load } from "cheerio";

interface EvidenceField {
  raw_value: string | null;
  normalized_value: string | number | boolean | null;
  evidence_ids: string[];
  confidence: number | null;
  user_confirmed: false;
  origin: "extracted";
  updated_at: string;
}

interface RecipeNode {
  [key: string]: unknown;
}

interface SourceMetadata {
  originalURL: string;
  canonicalURL: string;
  platformHint: string | null;
}

const MAX_JSON_LD_SCRIPTS = 50;
const MAX_JSON_LD_NODES = 2_000;
const MAX_JSON_LD_DEPTH = 64;

export interface ParsedWebRecipe {
  recipe_id: string;
  status: "ready" | "needs_review";
  source: {
    input_type: "url";
    original_url: string;
    canonical_url: string;
    platform: string | null;
    author_name: string | null;
    source_title: string | null;
  };
  fields: Record<string, EvidenceField>;
  evidence: Array<Record<string, unknown>>;
  review_fields: string[];
}

function isObject(value: unknown): value is RecipeNode {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isRecipeType(value: unknown): boolean {
  const values = Array.isArray(value) ? value : [value];
  return values.some((item) =>
    typeof item === "string" &&
    (item === "Recipe" || item.endsWith("/Recipe") || item.endsWith("#Recipe"))
  );
}

function recipeNodes(html: string): {
  nodes: RecipeNode[];
  malformed: boolean;
  excerpts: string[];
  sourceTitle: string | null;
} {
  const $ = load(html, { scriptingEnabled: false });
  const sourceTitle = textValue(
    $("meta[property='og:title']").attr("content") ?? $("title").text(),
  );
  const nodes: RecipeNode[] = [];
  const visited = new Set<object>();
  let malformed = false;
  const excerpts: string[] = [];

  const visit = (value: unknown, depth = 0): void => {
    if (depth > MAX_JSON_LD_DEPTH || visited.size >= MAX_JSON_LD_NODES) {
      malformed = true;
      return;
    }
    if (Array.isArray(value)) {
      for (const item of value.slice(0, MAX_JSON_LD_NODES)) {
        visit(item, depth + 1);
      }
      if (value.length > MAX_JSON_LD_NODES) malformed = true;
      return;
    }
    if (!isObject(value) || visited.has(value)) return;
    visited.add(value);

    if (isRecipeType(value["@type"])) {
      nodes.push(value);
      return;
    }
    for (const key of ["@graph", "mainEntity", "itemListElement", "hasPart"]) {
      if (key in value) visit(value[key], depth + 1);
    }
  };

  let scriptCount = 0;
  $("script[type]").each((_index, element) => {
    const mediaType = ($(element).attr("type") ?? "").split(";", 1)[0]
      .trim().toLowerCase();
    if (mediaType !== "application/ld+json") return;
    if (scriptCount >= MAX_JSON_LD_SCRIPTS) {
      malformed = true;
      return false;
    }
    scriptCount++;
    const text = $(element).text().trim();
    if (!text) return;
    excerpts.push(text);
    try {
      visit(JSON.parse(text));
    } catch {
      malformed = true;
    }
  });

  return { nodes, malformed, excerpts, sourceTitle };
}

function textValue(value: unknown): string | null {
  if (typeof value === "string") return value.trim() || null;
  if (Array.isArray(value)) {
    return value.map(textValue).filter((item): item is string => item !== null)
      .join(", ") || null;
  }
  if (!isObject(value)) return null;
  if (typeof value.name === "string") return textValue(value.name);
  if (typeof value.text === "string") return textValue(value.text);
  return null;
}

function ingredientValues(value: unknown): string[] {
  if (typeof value === "string") return value.trim() ? [value] : [];
  if (!Array.isArray(value)) {
    return value == null ? [] : [JSON.stringify(value)];
  }
  return value.flatMap((item) => {
    if (typeof item === "string") return item.trim() ? [item] : [];
    if (isObject(item) && typeof item.text === "string") return [item.text];
    // Preserve unrecognized structured quantities as source JSON; never
    // convert a unit code or approximate value into a guessed measurement.
    return [JSON.stringify(item)];
  });
}

function instructionValues(value: unknown): string[] {
  if (typeof value === "string") return value.trim() ? [value] : [];
  if (Array.isArray(value)) return value.flatMap(instructionValues);
  if (!isObject(value)) return [];
  if (typeof value.text === "string") return [value.text];
  for (const key of ["itemListElement", "steps"]) {
    if (key in value) return instructionValues(value[key]);
  }
  return [];
}

export function parseSchemaOrgRecipePage(input: {
  id: string;
  html: string;
  source: SourceMetadata;
}): ParsedWebRecipe {
  const { nodes, malformed, excerpts, sourceTitle: pageName } = recipeNodes(
    input.html,
  );
  const evidenceID = crypto.randomUUID();
  const timestamp = new Date().toISOString();
  const fields: Record<string, EvidenceField> = {};
  const reviewFields = new Set<string>();
  let authorName: string | null = null;

  const excerpt = nodes.length > 1
    ? `Multiple Recipe JSON-LD candidates (${nodes.length}): ${
      nodes.map((node) => textValue(node.name) ?? "untitled").join("; ")
    }. ${JSON.stringify(nodes).slice(0, 9_700)}`
    : nodes.length === 1
    ? JSON.stringify(nodes[0]).slice(0, 10_000)
    : malformed
    ? "Recipe JSON-LD was present but malformed; no recipe fields were inferred."
    : excerpts.length
    ? "JSON-LD was present, but no Schema.org Recipe object was found."
    : "No Schema.org Recipe JSON-LD object was found in the downloaded HTML.";

  const evidence = [{
    id: evidenceID,
    source_type: "webpage_structured_data",
    origin: "extracted",
    excerpt: excerpt.slice(0, 10_000),
    confidence: 1,
    captured_at: timestamp,
  }];

  const addField = (path: string, raw: string): void => {
    fields[path] = {
      raw_value: raw,
      normalized_value: null,
      evidence_ids: [evidenceID],
      confidence: 0.95,
      user_confirmed: false,
      origin: "extracted",
      updated_at: timestamp,
    };
  };

  if (nodes.length > 1) {
    reviewFields.add("recipe_selection");
    reviewFields.add("title");
    reviewFields.add("ingredients");
    reviewFields.add("steps");
  } else if (nodes.length === 1) {
    const recipe = nodes[0];
    const title = textValue(recipe.name);
    const ingredients = ingredientValues(recipe.recipeIngredient);
    const instructions = instructionValues(recipe.recipeInstructions);
    authorName = textValue(recipe.author);
    if (malformed) reviewFields.add("structured_data");

    if (title) addField("title", title);
    else reviewFields.add("title");
    if (ingredients.length > 0) {
      ingredients.forEach((raw, index) => {
        addField(`ingredients[${index}].raw_text`, raw);
        addField(`ingredients[${index}].amount`, raw);
      });
    } else {
      reviewFields.add("ingredients");
    }
    if (instructions.length > 0) {
      instructions.forEach((raw, index) => {
        addField(`steps[${index}].instruction`, raw);
      });
    } else {
      reviewFields.add("steps");
    }
  } else {
    reviewFields.add("title");
    reviewFields.add("ingredients");
    reviewFields.add("steps");
    if (malformed) reviewFields.add("structured_data");
  }

  return {
    recipe_id: input.id,
    status: reviewFields.size ? "needs_review" : "ready",
    source: {
      input_type: "url",
      original_url: input.source.originalURL,
      canonical_url: input.source.canonicalURL,
      platform: input.source.platformHint,
      author_name: authorName,
      source_title: pageName,
    },
    fields,
    evidence,
    review_fields: [...reviewFields],
  };
}
