// Developer: gengyun
// Purpose: Extract only evidenced Schema.org Recipe JSON-LD fields from public HTML.

import { load } from "cheerio";
import { publicSocialMetadata } from "./publicSocialMetadata.ts";
import type { PageTextEvidence } from "./pageContent.ts";
import { publicSocialSourceIdentity } from "./socialSource.ts";

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
    input_type: "url" | "text" | "image" | "file";
    original_url: string | null;
    canonical_url: string | null;
    source_artifact_id?: string | null;
    platform: string | null;
    author_name: string | null;
    source_title: string | null;
    external_content_id?: string | null;
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
  pageAuthor: string | null;
} {
  const $ = load(html, { scriptingEnabled: false });
  const sourceTitle = textValue(
    $("meta[property='og:title']").attr("content") ?? $("title").text(),
  )?.slice(0, 240) ?? null;
  const pageAuthor = textValue(
    $("meta[property='article:author']").attr("content") ??
      $("meta[name='author']").attr("content"),
  )?.slice(0, 160) ?? null;
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

  return { nodes, malformed, excerpts, sourceTitle, pageAuthor };
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
  const { nodes, malformed, excerpts, sourceTitle: pageName, pageAuthor } =
    recipeNodes(input.html);
  const identity = publicSocialSourceIdentity(input.source.canonicalURL);
  const social = publicSocialMetadata(input.html, input.source.canonicalURL);
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
    authorName = textValue(recipe.author) ?? pageAuthor;
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
    authorName = pageAuthor;
  }

  return {
    recipe_id: input.id,
    status: reviewFields.size ? "needs_review" : "ready",
    source: {
      input_type: "url",
      original_url: input.source.originalURL,
      canonical_url: input.source.canonicalURL,
      source_artifact_id: null,
      platform: identity?.platform ?? social.platform ?? input.source.platformHint,
      author_name: authorName ?? social.authorName,
      source_title: pageName ?? social.title,
      external_content_id: identity?.id ?? null,
    },
    fields,
    evidence,
    review_fields: [...reviewFields],
  };
}

export function incompleteWebRecipe(input: {
  id: string;
  originalURL: string;
  platformHint: string | null;
}): ParsedWebRecipe {
  const identity = publicSocialSourceIdentity(input.originalURL);
  return {
    recipe_id: input.id,
    status: "needs_review",
    source: {
      input_type: "url",
      original_url: input.originalURL,
      canonical_url: null,
      source_artifact_id: null,
      platform: identity?.platform ?? input.platformHint,
      author_name: null,
      source_title: null,
      external_content_id: identity?.id ?? null,
    },
    fields: {},
    evidence: [],
    review_fields: ["title", "ingredients", "steps"],
  };
}

export function incompleteArtifactRecipe(input: {
  id: string;
  inputType: "image" | "file";
  artifactID: string;
  platformHint: string | null;
  mimeType: string | null;
}): ParsedWebRecipe {
  const capturedAt = new Date().toISOString();
  const evidenceID = crypto.randomUUID();
  const kind = input.inputType === "image" ? "image" : "file";
  return {
    recipe_id: input.id,
    status: "needs_review",
    source: {
      input_type: input.inputType,
      original_url: null,
      canonical_url: null,
      source_artifact_id: input.artifactID,
      platform: input.platformHint,
      author_name: null,
      source_title: null,
    },
    fields: {},
    evidence: [{
      id: evidenceID,
      source_type: "user",
      source_artifact_id: input.artifactID,
      origin: "user",
      excerpt: `User-provided ${kind} source retained privately (${input.mimeType ?? "unknown file type"}). Text extraction is unavailable for this cloud import.`,
      confidence: null,
      captured_at: capturedAt,
    }],
    review_fields: ["title", "ingredients", "steps", "artifact_text"],
  };
}

export function attachPageTextEvidence(
  recipe: ParsedWebRecipe,
  pageEvidence: PageTextEvidence[],
): ParsedWebRecipe {
  if (pageEvidence.length === 0) return recipe;

  const fields = { ...recipe.fields };
  const reviewFields = new Set(recipe.review_fields);
  const evidence = [
    ...recipe.evidence,
    ...pageEvidence.map((item) => ({
      id: item.id,
      source_type: item.sourceType,
      origin: "extracted",
      excerpt: item.excerpt,
      confidence: null,
      captured_at: item.capturedAt,
    })),
  ];

  // Multiple structured recipes are ambiguous; never pick one from nearby copy.
  if (!reviewFields.has("recipe_selection")) {
    for (const item of pageEvidence) {
      const sections = sectionValues(item.text);
      if (
        !fields.title && item.sourceType === "article_body" && item.title &&
        item.text.includes(item.title)
      ) {
        fields.title = pageField(item, item.title);
        reviewFields.delete("title");
      }
      if (
        !hasFieldPrefix(fields, "ingredients") && sections.ingredients.length
      ) {
        sections.ingredients.forEach((value, index) => {
          fields[`ingredients[${index}].raw_text`] = pageField(item, value);
          fields[`ingredients[${index}].amount`] = pageField(item, value);
        });
        reviewFields.delete("ingredients");
      }
      if (!hasFieldPrefix(fields, "steps") && sections.steps.length) {
        sections.steps.forEach((value, index) => {
          fields[`steps[${index}].instruction`] = pageField(item, value);
        });
        reviewFields.delete("steps");
      }
    }
  }

  const nextReviewFields = [...reviewFields];
  return {
    ...recipe,
    status: nextReviewFields.length ? "needs_review" : "ready",
    fields,
    evidence,
    review_fields: nextReviewFields,
  };
}

function pageField(
  source: PageTextEvidence,
  rawValue: string,
): EvidenceField {
  return {
    raw_value: rawValue,
    normalized_value: null,
    evidence_ids: [source.id],
    confidence: null,
    user_confirmed: false,
    origin: "extracted",
    updated_at: source.capturedAt,
  };
}

function hasFieldPrefix(
  fields: Record<string, EvidenceField>,
  prefix: string,
): boolean {
  return Object.keys(fields).some((path) => path.startsWith(`${prefix}[`));
}

function sectionValues(text: string): { ingredients: string[]; steps: string[] } {
  const ingredients: string[] = [];
  const steps: string[] = [];
  const ingredientHeading =
    /^(?:ingredients?|ingredient list|食材|材料|原料|材料一覧)\s*[:：]?$/i;
  const stepHeading =
    /^(?:steps?|instructions?|directions?|preparations?|method|做法|步骤|步骤说明|作り方|手順)\s*[:：]?$/i;
  const otherHeading =
    /^(?:notes?|tips?|variations?|nutrition|equipment|storage|comments?|nutrition facts|description|about|备注|提示|小贴士|营养信息|简介)\s*[:：]?$/i;
  let section: "none" | "ingredients" | "steps" = "none";

  for (const line of text.split(/\r?\n/)) {
    const value = line.trim();
    if (!value) continue;
    if (ingredientHeading.test(value)) {
      section = "ingredients";
      continue;
    }
    if (stepHeading.test(value)) {
      section = "steps";
      continue;
    }
    if (otherHeading.test(value)) {
      section = "none";
      continue;
    }
    if (section !== "none" && value.length <= 60 && /[:：]$/.test(value)) {
      section = "none";
      continue;
    }

    const raw = value.replace(/^(?:[-*•]\s*|\d+[).、]\s*)/, "");
    if (section === "ingredients" && ingredients.length < 100) {
      ingredients.push(raw);
    } else if (section === "steps" && steps.length < 80) {
      steps.push(raw);
    }
  }

  return { ingredients, steps };
}
