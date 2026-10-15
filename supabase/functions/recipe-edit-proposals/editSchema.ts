// Developer: gengyun
// Purpose: Strict edit-v1 wire validators for the three AI recipe edit change paths.

export type EditIntent = "substitute" | "simplify" | "dietary";
export const EDIT_INTENTS: readonly EditIntent[] = [
  "substitute",
  "simplify",
  "dietary",
];

/** Lowercase RFC UUID; uppercase is rejected to match the Swift decoder. */
export const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const HASH = /^[a-f0-9]{64}$/;

const INGREDIENT_PATH = new RegExp(
  `^ingredient:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:(name|amount)$`,
);
const STEP_PATH = new RegExp(
  `^step:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:instruction$`,
);

export interface EditChange {
  path: string;
  original: string;
  proposed: string;
  reason: string;
  warnings: string[];
}

const MAX_CHANGES = 30;
const MAX_REASONS = 8;
const MAX_WARNINGS = 8;
const MAX_TEXT = 300;
const NAME_AMOUNT_MAX = 240;
const INSTRUCTION_MAX = 8000;

// Mirrors RecipeEditProposal.safeText: trimmed non-empty, bounded length, no control chars.
export function editTextValid(
  value: unknown,
  maximum: number,
): value is string {
  if (typeof value !== "string") return false;
  // Bounds apply to the raw string so TS and SQL recipe_edit_text_valid agree exactly.
  if (value.trim().length === 0 || value.length > maximum) return false;
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(value)) return false;
  return true;
}

function hasDuplicates(items: readonly string[]): boolean {
  const seen = new Set<string>();
  for (const item of items) {
    if (seen.has(item)) return true;
    seen.add(item);
  }
  return false;
}

export function validEditPath(path: unknown): path is string {
  return typeof path === "string" &&
    (INGREDIENT_PATH.test(path) || STEP_PATH.test(path));
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validEditChange(value: unknown): value is EditChange {
  if (!isObject(value)) return false;
  if (Object.keys(value).length !== 5) return false;
  const { path, original, proposed, reason, warnings } = value;
  if (!validEditPath(path)) return false;
  const maximum = INGREDIENT_PATH.test(path)
    ? NAME_AMOUNT_MAX
    : INSTRUCTION_MAX;
  if (!editTextValid(original, maximum) || !editTextValid(proposed, maximum)) {
    return false;
  }
  if (original === proposed) return false;
  if (!editTextValid(reason, MAX_TEXT)) return false;
  if (!Array.isArray(warnings) || warnings.length > MAX_WARNINGS) return false;
  if (!warnings.every((item) => editTextValid(item, MAX_TEXT))) return false;
  if (hasDuplicates(warnings)) return false;
  return true;
}

/** Strict edit-v1 change-set: only the three value-replacement paths. */
export function validEditChanges(value: unknown): value is EditChange[] {
  if (!Array.isArray(value)) return false;
  if (value.length < 1 || value.length > MAX_CHANGES) return false;
  if (!value.every(validEditChange)) return false;
  if (hasDuplicates(value.map((change) => change.path))) return false;
  return true;
}

export function validReasons(value: unknown): value is string[] {
  if (!Array.isArray(value) || value.length > MAX_REASONS) return false;
  return value.every((item) => editTextValid(item, MAX_TEXT));
}

export function validWarnings(value: unknown): value is string[] {
  if (!Array.isArray(value) || value.length > MAX_WARNINGS) return false;
  return value.every((item) => editTextValid(item, MAX_TEXT));
}

export function isEditIntent(value: unknown): value is EditIntent {
  return typeof value === "string" &&
    (EDIT_INTENTS as readonly string[]).includes(value);
}
