// Developer: gengyun
// Purpose: DEV-438 server-internal metering helper for the three phase-II premium capabilities. It
//          validates the internal origin shapes, computes the canonical input_hash, and wraps the two
//          service-role-only ledger RPCs (reserve_internal / finalize_internal) plus the reused
//          capability-agnostic dispatch/release RPCs. The public V1 save DTO, origin enum and policy
//          schema_version are untouched: only service-role Edge handlers call these entry points.

import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";

type Row = Record<string, unknown>;

/** The three premium capabilities that settle through the server-internal extension. */
export type InternalCapability =
  | "recipe_question"
  | "recipe_translation"
  | "media_import";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const INTERNAL_CAPABILITIES: Record<InternalCapability, true> = {
  recipe_question: true,
  recipe_translation: true,
  media_import: true,
};

/** recipe_question binds the recipe context and the per-turn idempotency key. */
export interface RecipeQuestionSource {
  origin: "recipe_question";
  recipe_id: string;
  turn_request_id: string;
}

/** recipe_translation binds the persisted, owned translation proposal. */
export interface RecipeTranslationSource {
  origin: "recipe_translation";
  proposal_id: string;
}

/** media_import binds the persisted, owned media task. */
export interface MediaImportSource {
  origin: "media_import";
  media_task_id: string;
}

export type InternalSource =
  | RecipeQuestionSource
  | RecipeTranslationSource
  | MediaImportSource;

/** Durable outcome kinds bound to an already-persisted owned result row. */
export type InternalResultKind = "answer" | "translation" | "media_task";

function isUUID(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

/** Exactly the bound field for the capability; no other internal origin field may be set. */
function isQuestionSource(value: unknown): value is RecipeQuestionSource {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const row = value as Row;
  return row.origin === "recipe_question" &&
    isUUID(row.recipe_id) && isUUID(row.turn_request_id) &&
    !("proposal_id" in row) && !("media_task_id" in row);
}

function isTranslationSource(value: unknown): value is RecipeTranslationSource {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const row = value as Row;
  return row.origin === "recipe_translation" && isUUID(row.proposal_id) &&
    !("recipe_id" in row) && !("turn_request_id" in row) &&
    !("media_task_id" in row);
}

function isMediaImportSource(value: unknown): value is MediaImportSource {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const row = value as Row;
  return row.origin === "media_import" && isUUID(row.media_task_id) &&
    !("recipe_id" in row) && !("turn_request_id" in row) &&
    !("proposal_id" in row);
}

/** Fail-closed validation of the internal origin allowlist against the capability. */
export function validateInternalSource(
  capability: InternalCapability,
  source: unknown,
): source is InternalSource {
  switch (capability) {
    case "recipe_question":
      return isQuestionSource(source);
    case "recipe_translation":
      return isTranslationSource(source);
    case "media_import":
      return isMediaImportSource(source);
  }
}

export function internalSourceForQuestion(
  recipeID: string,
  turnRequestID: string,
): RecipeQuestionSource {
  return {
    origin: "recipe_question",
    recipe_id: recipeID,
    turn_request_id: turnRequestID,
  };
}

export function internalSourceForTranslation(
  proposalID: string,
): RecipeTranslationSource {
  return { origin: "recipe_translation", proposal_id: proposalID };
}

export function internalSourceForMediaImport(
  mediaTaskID: string,
): MediaImportSource {
  return { origin: "media_import", media_task_id: mediaTaskID };
}

export function isInternalCapability(
  value: unknown,
): value is InternalCapability {
  return typeof value === "string" && value in INTERNAL_CAPABILITIES;
}

/**
 * input_hash = lowercase SHA-256 of the UTF-8 bytes of canonicalJSON({capability, source}). It is
 * immutable across reserve -> dispatch -> finalize and is NOT the persisted answer/payload hash.
 */
export function computeInternalInputHash(
  capability: InternalCapability,
  source: InternalSource,
): Promise<string> {
  return canonicalHash({ capability, source });
}

/** The service-role RPC adapter injected by the calling Edge function. */
export type InternalUsageRPC = (name: string, args: Row) => Promise<Row>;

export type InternalUsageResult = Row & { code?: string };

function rpcRow(value: unknown): Row {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("internal_usage_rpc_invalid_response");
  }
  return value as Row;
}

/** Reserve one unit through the service-role-only internal entry point. */
export async function reserveInternal(
  rpc: InternalUsageRPC,
  ownerID: string,
  operationID: string,
  capability: InternalCapability,
  inputHash: string,
  source: InternalSource,
): Promise<InternalUsageResult> {
  return rpcRow(
    await rpc("recipe_usage_reserve_internal", {
      p_owner_id: ownerID,
      p_operation_id: operationID,
      p_capability: capability,
      p_input_hash: inputHash,
      p_source: source,
    }),
  );
}

/** Transition a still-reserved unit to dispatched_unknown before the provider side effect. */
export async function markDispatchedInternal(
  rpc: InternalUsageRPC,
  ownerID: string,
  operationID: string,
): Promise<InternalUsageResult> {
  return rpcRow(
    await rpc("recipe_usage_mark_dispatched", {
      p_owner_id: ownerID,
      p_operation_id: operationID,
    }),
  );
}

/** Settle the reservation once and bind the durable outcome to a persisted owned result row. */
export async function finalizeInternal(
  rpc: InternalUsageRPC,
  ownerID: string,
  operationID: string,
  capability: InternalCapability,
  inputHash: string,
  source: InternalSource,
  recipeID: string | null,
  payloadHash: string,
  payload: Row,
  resultKind: InternalResultKind,
  resultID: string,
): Promise<InternalUsageResult> {
  return rpcRow(
    await rpc("recipe_usage_finalize_internal", {
      p_owner_id: ownerID,
      p_operation_id: operationID,
      p_capability: capability,
      p_input_hash: inputHash,
      p_source: source,
      p_recipe_id: recipeID,
      p_payload_hash: payloadHash,
      p_payload: payload,
      p_result_kind: resultKind,
      p_result_id: resultID,
    }),
  );
}

/** Release a reservation confirmed not dispatched or not committed (capability-agnostic reuse). */
export async function releaseInternal(
  rpc: InternalUsageRPC,
  ownerID: string,
  operationID: string,
): Promise<InternalUsageResult> {
  return rpcRow(
    await rpc("recipe_usage_release", {
      p_owner_id: ownerID,
      p_operation_id: operationID,
    }),
  );
}

/** Release a dispatched reservation whose outcome the caller has definitively determined is failed
 *  and non-recoverable (bypasses the unknown-outcome fence deliberately). Used only when the provider
 *  was invoked and returned a known-invalid result, never for ambiguous transport failures. */
export async function releaseFailedInternal(
  rpc: InternalUsageRPC,
  ownerID: string,
  operationID: string,
): Promise<InternalUsageResult> {
  return rpcRow(
    await rpc("recipe_usage_release_failed", {
      p_owner_id: ownerID,
      p_operation_id: operationID,
    }),
  );
}
