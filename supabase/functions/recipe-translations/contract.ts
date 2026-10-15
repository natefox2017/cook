// Developer: gengyun
// Purpose: Pure request/output validation for the recipe-translations contract.

export const TARGET_LOCALES = ["en", "zh-Hans", "zh-Hant", "ja"] as const;
export type TargetLocale = (typeof TARGET_LOCALES)[number];

export const MAX_INPUT_BYTES = 32 * 1024;
export const MAX_OUTPUT_BYTES = 64 * 1024;
export const DEADLINE_MS = 60_000;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// Must agree with RecipeTranslationProposal.preservesNumericTokens in RecipeCore.
const NUMBER_RE = /\d+\/\d+|\d+(?:\.\d+)?|\.\d+/g;
const REVISION_RE = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/;

export class TranslationContractError extends Error {
  constructor(
    public readonly code:
      | "validation_error"
      | "unsupported_locale"
      | "oversized"
      | "invalid_provider_output",
    message: string,
  ) {
    super(message);
    this.name = "TranslationContractError";
  }
}

export interface TranslationIngredient {
  id: string;
  name: string;
  amount_text: string;
}

export interface TranslationStep {
  id: string;
  title: string;
  instruction: string;
}

export interface TranslationRecipeInput {
  title: string;
  summary: string;
  ingredients: TranslationIngredient[];
  steps: TranslationStep[];
  source_url: string | null;
  source_name: string | null;
}

export interface TranslationRequest {
  target_locale: TargetLocale;
  recipe: TranslationRecipeInput;
  /** Source recipe id (owner-scoped revision/ownership fence). */
  recipe_id: string;
  /** Source recipe updatedAt, canonical millisecond UTC (server compares to the stored row). */
  expected_revision: string;
  /** Client-stable idempotency key retained across retries; binds the metered operation. */
  proposal_id: string;
}

export interface TranslationField {
  id: string;
  original: string;
  translated: string;
}

export interface TranslationProposal {
  target_locale: TargetLocale;
  title: string;
  summary: string;
  ingredient_names: TranslationField[];
  ingredient_amounts: TranslationField[];
  step_instructions: TranslationField[];
  step_titles: TranslationField[];
  source_url: string | null;
  source_name: string | null;
}

function requireText(value: unknown, maximum: number): string {
  if (typeof value !== "string") {
    throw new TranslationContractError("validation_error", "Expected a string field.");
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maximum) {
    throw new TranslationContractError("oversized", "Text field is empty or too long.");
  }
  // Reject control characters; provider text must never pass through verbatim.
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)) {
    throw new TranslationContractError("validation_error", "Text field contains control characters.");
  }
  return value;
}

function requireUUID(value: unknown): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw new TranslationContractError("validation_error", "Expected a lowercase UUID.");
  }
  return value;
}

function requireRevision(value: unknown): string {
  if (typeof value !== "string" || !REVISION_RE.test(value)) {
    throw new TranslationContractError("validation_error", "Expected an ISO-8601 millisecond revision.");
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new TranslationContractError("validation_error", "Invalid revision.");
  }
  return parsed.toISOString();
}

function requireIngredient(value: unknown): TranslationIngredient {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TranslationContractError("validation_error", "Expected an ingredient object.");
  }
  const entry = value as Record<string, unknown>;
  return {
    id: requireUUID(entry.id),
    name: requireText(entry.name, 240),
    amount_text: typeof entry.amount_text === "string" ? entry.amount_text : "",
  };
}

function requireStep(value: unknown): TranslationStep {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TranslationContractError("validation_error", "Expected a step object.");
  }
  const entry = value as Record<string, unknown>;
  return {
    id: requireUUID(entry.id),
    title: typeof entry.title === "string" ? entry.title : "",
    instruction: requireText(entry.instruction, 8_000),
  };
}

function requireFieldList(
  value: unknown,
  maximum: number,
): Array<{ id: string; translated: string }> {
  if (!Array.isArray(value) || value.length > maximum) {
    throw new TranslationContractError("oversized", "Field list is missing or too long.");
  }
  const seen = new Set<string>();
  return value.map((item) => {
    if (typeof item !== "object" || item === null || Array.isArray(item)) {
      throw new TranslationContractError("validation_error", "Expected a field object.");
    }
    const entry = item as Record<string, unknown>;
    const id = requireUUID(entry.id);
    if (seen.has(id)) {
      throw new TranslationContractError("validation_error", "Duplicated field id.");
    }
    seen.add(id);
    return { id, translated: requireText(entry.translated, 8_000) };
  });
}

/** Parses a bounded request body; unknown or malformed shapes fail closed. */
export function parseRequest(body: Record<string, unknown>): TranslationRequest {
  const locale = body.target_locale;
  if (typeof locale !== "string" || !(TARGET_LOCALES as readonly string[]).includes(locale)) {
    throw new TranslationContractError("unsupported_locale", "Unsupported target locale.");
  }
  if (typeof body.recipe !== "object" || body.recipe === null || Array.isArray(body.recipe)) {
    throw new TranslationContractError("validation_error", "Expected a recipe object.");
  }
  const recipe = body.recipe as Record<string, unknown>;
  const ingredients = Array.isArray(recipe.ingredients)
    ? recipe.ingredients.map(requireIngredient)
    : [];
  const steps = Array.isArray(recipe.steps) ? recipe.steps.map(requireStep) : [];
  if (ingredients.length > 200 || steps.length > 200) {
    throw new TranslationContractError("oversized", "Recipe has too many fields.");
  }
  const sourceURL = typeof recipe.source_url === "string" ? requireText(recipe.source_url, 2_048) : null;
  const sourceName = typeof recipe.source_name === "string" ? requireText(recipe.source_name, 240) : null;
  return {
    target_locale: locale as TargetLocale,
    recipe: {
      title: typeof recipe.title === "string" ? recipe.title : "",
      summary: typeof recipe.summary === "string" ? recipe.summary : "",
      ingredients,
      steps,
      source_url: sourceURL,
      source_name: sourceName,
    },
    recipe_id: requireUUID(body.recipe_id),
    expected_revision: requireRevision(body.expected_revision),
    proposal_id: requireUUID(body.proposal_id),
  };
}

function numericTokens(value: string): string[] {
  return (value.match(NUMBER_RE) ?? []).map((token) => token.trim()).sort();
}

/** Numbers in translated prose must be a permutation of the source numbers (shared with Swift). */
function preservesNumericTokens(original: string, translated: string): boolean {
  return numericTokens(original).join("\u0000") === numericTokens(translated).join("\u0000");
}

/** Builds a structured-translation prompt that forbids numeric or structural changes. */
export function buildPrompt(request: TranslationRequest): string {
  const target = request.target_locale;
  return [
    "Translate a private recipe into the target language. Translate only natural-language text:",
    "the title, summary, ingredient names, vague amount text, and step instructions/titles.",
    "Keep every number, fraction, unit, and temperature verbatim using Arabic numerals.",
    "Never convert or invent amounts; keep ingredient and step count and order unchanged.",
    "Do not translate images, videos, or notes. Return only JSON matching this shape:",
    JSON.stringify({
      title: "string",
      summary: "string",
      ingredient_names: [{ id: "string", translated: "string" }],
      ingredient_amounts: [{ id: "string", translated: "string" }],
      step_instructions: [{ id: "string", translated: "string" }],
      step_titles: [{ id: "string", translated: "string" }],
    }),
    `target_locale: ${target}`,
    "recipe:",
    JSON.stringify(request.recipe),
  ].join("\n");
}

/** Validates provider output against the input, preserving stable mapping and numbers. */
export function validateProviderOutput(
  raw: unknown,
  request: TranslationRequest,
): TranslationProposal {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TranslationContractError("invalid_provider_output", "Provider returned non-object JSON.");
  }
  const output = raw as Record<string, unknown>;

  const title = output.title === undefined ? "" : requireText(output.title, 240);
  const summary = output.summary === undefined ? "" : requireText(output.summary, 4_000);

  const ingredientNames = output.ingredient_names === undefined
    ? []
    : requireFieldList(output.ingredient_names, 200);
  const names: TranslationField[] = [];
  if (ingredientNames.length > 0) {
    if (ingredientNames.length !== request.recipe.ingredients.length) {
      throw new TranslationContractError("invalid_provider_output", "Ingredient count changed.");
    }
    for (const [index, source] of request.recipe.ingredients.entries()) {
      const entry = ingredientNames[index];
      if (!entry || entry.id !== source.id) {
        throw new TranslationContractError("invalid_provider_output", "Ingredient mapping changed.");
      }
      names.push({ id: source.id, original: source.name, translated: entry.translated });
    }
  }

  const amountEntries = output.ingredient_amounts === undefined
    ? []
    : requireFieldList(output.ingredient_amounts, 200);
  const ingredientAmounts: TranslationField[] = amountEntries.map((entry) => {
    const source = request.recipe.ingredients.find((item) => item.id === entry.id);
    if (!source) {
      throw new TranslationContractError("invalid_provider_output", "Unknown ingredient amount id.");
    }
    if (!preservesNumericTokens(source.amount_text, entry.translated)) {
      throw new TranslationContractError("invalid_provider_output", "Amount numbers changed.");
    }
    return { id: source.id, original: source.amount_text, translated: entry.translated };
  });

  const stepInstructions = output.step_instructions === undefined
    ? []
    : requireFieldList(output.step_instructions, 200);
  const instructions: TranslationField[] = [];
  if (stepInstructions.length > 0) {
    if (stepInstructions.length !== request.recipe.steps.length) {
      throw new TranslationContractError("invalid_provider_output", "Step count changed.");
    }
    for (const [index, source] of request.recipe.steps.entries()) {
      const entry = stepInstructions[index];
      if (!entry || entry.id !== source.id) {
        throw new TranslationContractError("invalid_provider_output", "Step mapping changed.");
      }
      if (!preservesNumericTokens(source.instruction, entry.translated)) {
        throw new TranslationContractError("invalid_provider_output", "Step numbers changed.");
      }
      instructions.push({ id: source.id, original: source.instruction, translated: entry.translated });
    }
  }

  const stepTitleEntries = output.step_titles === undefined
    ? []
    : requireFieldList(output.step_titles, 200);
  const stepTitles: TranslationField[] = stepTitleEntries.map((entry) => {
    const source = request.recipe.steps.find((item) => item.id === entry.id);
    if (!source) {
      throw new TranslationContractError("invalid_provider_output", "Unknown step title id.");
    }
    return { id: source.id, original: source.title, translated: entry.translated };
  });

  if (
    title === "" && summary === "" && names.length === 0 &&
    ingredientAmounts.length === 0 && instructions.length === 0 && stepTitles.length === 0
  ) {
    throw new TranslationContractError("invalid_provider_output", "Provider returned an empty proposal.");
  }

  return {
    target_locale: request.target_locale,
    title,
    summary,
    ingredient_names: names,
    ingredient_amounts: ingredientAmounts,
    step_instructions: instructions,
    step_titles: stepTitles,
    source_url: request.recipe.source_url,
    source_name: request.recipe.source_name,
  };
}
