// Developer: gengyun
// Purpose: Freeze the DEV-428 draft-composition contract: apply an accepted approval's selected
//          suggestion paths onto the immutable turn context and return the saveable ready recipe
//          fields. Pure and deterministic so the DEV-429 iOS client can mirror it for a matching
//          payload_hash; DEV-431 payload paths reuse the same field shape.

import { scalarString } from "./canonicalJSON.ts";

type Row = Record<string, unknown>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const PATH =
  /^(title|servings|ingredients\[(?:[0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[(?:[0-9]|[1-9][0-9])\]\.instruction)$/;
const REVIEW_GROUP: Record<string, true> = {
  ingredients: true,
  steps: true,
};
const MAX_REV = 9223372036854775807n;

/** A confirmed draft field exactly as the wire/DB context carries it. */
export interface DraftField {
  raw_value: string | null;
  evidence_ids: string[];
  user_confirmed: boolean;
  origin: string;
}

export interface DraftEvidence {
  id: string;
  excerpt: string;
}

/**
 * The composed "saveable recipe": the immutable context after the accepted suggestion paths are
 * applied. `review_fields` is always empty — a composition with unresolved review fields is not a
 * saveable recipe and is returned as `null` instead.
 */
export interface ComposedDraftRecipe {
  status: "ready";
  fields: Record<string, DraftField>;
  evidence: DraftEvidence[];
  review_fields: string[];
}

/** The immutable ai_edit snapshot produced by DEV-427's `extractEditPayload`. */
export interface ApprovedDraftSnapshot {
  context_snapshot: Row;
  result: Row;
  selected_paths: string[];
  applied_revision: string;
}

function isObject(value: unknown): value is Row {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

function isRevision(value: unknown): value is string {
  return typeof value === "string" && /^[1-9][0-9]{0,18}$/.test(value) &&
    BigInt(value) <= MAX_REV;
}

function isPath(value: unknown): value is string {
  return typeof value === "string" && PATH.test(value);
}

function isReviewFlag(value: unknown): value is string {
  return typeof value === "string" &&
    (PATH.test(value) || REVIEW_GROUP[value] === true);
}

function parseField(value: unknown): DraftField | null {
  if (!isObject(value) || Object.keys(value).length !== 4) return null;
  const raw = value.raw_value;
  if (raw !== null && !scalarString(raw, 1, 1500)) return null;
  const ids = value.evidence_ids;
  if (!Array.isArray(ids) || ids.length > 60) return null;
  if (!ids.every(isUUID) || new Set(ids).size !== ids.length) return null;
  if (typeof value.user_confirmed !== "boolean") return null;
  if (!scalarString(value.origin, 1, 64)) return null;
  return {
    raw_value: raw as string | null,
    evidence_ids: ids as string[],
    user_confirmed: value.user_confirmed as boolean,
    origin: value.origin as string,
  };
}

interface ParsedContext {
  status: "ready" | "needs_review";
  fields: Record<string, DraftField>;
  evidence: DraftEvidence[];
  reviewFields: string[];
}

function parseContext(value: unknown): ParsedContext | null {
  if (!isObject(value) || Object.keys(value).length !== 4) return null;
  if (value.status !== "ready" && value.status !== "needs_review") return null;
  if (!isObject(value.fields) || Object.keys(value.fields).length > 100) {
    return null;
  }
  const fields: Record<string, DraftField> = Object.create(null);
  for (const [path, item] of Object.entries(value.fields)) {
    if (!isPath(path)) return null;
    const field = parseField(item);
    if (!field) return null;
    fields[path] = field;
  }
  if (!Array.isArray(value.evidence) || value.evidence.length > 60) return null;
  const seen = new Set<string>();
  const evidence: DraftEvidence[] = [];
  let total = 0;
  for (const item of value.evidence) {
    if (!isObject(item) || Object.keys(item).length !== 2) return null;
    if (!isUUID(item.id)) return null;
    if (!scalarString(item.excerpt, 1, 1500)) return null;
    if (seen.has(item.id as string)) return null;
    seen.add(item.id as string);
    total += [...(item.excerpt as string)].length;
    evidence.push({ id: item.id as string, excerpt: item.excerpt as string });
  }
  if (total > 20000) return null;
  for (const field of Object.values(fields)) {
    if (!field.evidence_ids.every((id) => seen.has(id))) return null;
  }
  if (!Array.isArray(value.review_fields) || value.review_fields.length > 100) {
    return null;
  }
  if (!value.review_fields.every(isReviewFlag)) return null;
  if (new Set(value.review_fields).size !== value.review_fields.length) {
    return null;
  }
  const flags = value.review_fields as string[];
  if ((value.status === "ready") !== (flags.length === 0)) return null;
  return {
    status: value.status as ParsedContext["status"],
    fields,
    evidence,
    reviewFields: flags,
  };
}

interface ParsedSuggestion {
  path: string;
  raw_value: string;
  evidence_ids: string[];
}

interface ParsedResult {
  suggestions: ParsedSuggestion[];
}

function parseResult(value: unknown): ParsedResult | null {
  if (!isObject(value)) return null;
  if (
    value.status !== "proposal" || value.origin !== "AI_suggested" ||
    value.requires_approval !== true
  ) return null;
  if (!Array.isArray(value.suggestions) || value.suggestions.length < 1 ||
    value.suggestions.length > 20) {
    return null;
  }
  const suggestions: ParsedSuggestion[] = [];
  const paths = new Set<string>();
  for (const item of value.suggestions) {
    if (!isObject(item) || Object.keys(item).length !== 4) return null;
    if (!isPath(item.path)) return null;
    if (!scalarString(item.raw_value, 1, 1500)) return null;
    const ids = item.evidence_ids;
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > 60) return null;
    if (!ids.every(isUUID) || new Set(ids).size !== ids.length) return null;
    if (!scalarString(item.reason, 1, 500)) return null;
    if (paths.has(item.path as string)) return null;
    paths.add(item.path as string);
    suggestions.push({
      path: item.path as string,
      raw_value: item.raw_value as string,
      evidence_ids: ids as string[],
    });
  }
  return { suggestions };
}

/**
 * Reconstruct the saveable ready recipe from the immutable snapshot. Returns `null` (fail-closed)
 * for any malformed shape, invalid selected path, or an approval that leaves review fields open.
 * This mirrors the server approval RPC's field application exactly and never invents a value.
 */
export function composeApprovedDraftFields(
  snapshot: unknown,
): ComposedDraftRecipe | null {
  if (!isObject(snapshot) || Object.keys(snapshot).length !== 4) return null;
  const context = parseContext(snapshot.context_snapshot);
  const result = parseResult(snapshot.result);
  if (!context || !result) return null;
  if (!isRevision(snapshot.applied_revision)) return null;

  const selected = snapshot.selected_paths;
  if (!Array.isArray(selected) || selected.length < 1 || selected.length > 20) {
    return null;
  }
  if (!selected.every(isPath) || new Set(selected).size !== selected.length) {
    return null;
  }

  const fields: Record<string, DraftField> = { ...context.fields };
  const flags = [...context.reviewFields];

  for (const path of selected as string[]) {
    const matches = result.suggestions.filter((item) => item.path === path);
    const existing = fields[path] ?? null;
    if (matches.length !== 1) return null;
    if (existing && existing.user_confirmed === true) return null;
    if (existing === null && !flags.includes(path)) return null;
    const flagged = flags.some((flag) =>
      flag === path ||
      (REVIEW_GROUP[flag] === true && path.startsWith(`${flag}[`))
    );
    if (!flagged) return null;
    const suggestion = matches[0];
    fields[path] = {
      raw_value: suggestion.raw_value,
      evidence_ids: suggestion.evidence_ids,
      user_confirmed: true,
      origin: "AI_suggested",
    };
  }

  // Resolve remaining review flags the same way the server approval RPC does.
  const remaining = flags.filter((flag) => {
    if (selected.includes(flag)) return false;
    if (REVIEW_GROUP[flag] !== true) return true;
    const keys = Object.keys(fields).filter((path) =>
      path.startsWith(`${flag}[`)
    );
    const exactFlags = flags.filter((path) => path.startsWith(`${flag}[`));
    return !(
      keys.length > 0 &&
      keys.every((path) => fields[path].user_confirmed === true) &&
      exactFlags.every((path) =>
        fields[path] !== undefined && fields[path].user_confirmed === true
      ) &&
      selected.some((path) => path.startsWith(`${flag}[`))
    );
  });

  if (remaining.length > 0) return null;

  return {
    status: "ready",
    fields,
    evidence: context.evidence,
    review_fields: [],
  };
}
