// Developer: gengyun
// Purpose: DEV-427 server runtime for the frozen commercial access/usage contract. It computes the
// canonical input_hash, resolves owner entitlement from the trusted subscriptions row, and extracts
// the approved payload that finalize persists. It never trusts a client success flag or quota field.

import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";

/** A minimally-decoded subscriptions row: status + expires_at decide entitlement. */
export interface SubscriptionRow {
  status?: string | null;
  expires_at?: string | null;
}

export interface Entitlement {
  status: "free" | "premium" | "expired";
  /** RFC3339 UTC with millisecond precision, or null for free/lifetime premium. */
  valid_until: string | null;
  /** The settlement tier: premium only while the trusted subscription is live. */
  tier: "free" | "premium";
}

const PREMIUM_STATUSES: Record<string, true> = {
  active: true,
  trialing: true,
  cancelled: true,
  billing_issue: true,
};

/**
 * Server-owned entitlement. A client can never assert premium: the tier comes only from the trusted
 * subscriptions lifecycle. Mirrors public.recipe_usage_entitlement in the migration exactly.
 */
export function resolveEntitlement(sub: SubscriptionRow | null): Entitlement {
  if (!sub) return { status: "free", valid_until: null, tier: "free" };
  const status = sub.status ?? "none";
  const expiresAt = sub.expires_at ?? null;
  const live = PREMIUM_STATUSES[status] === true &&
    (expiresAt === null || new Date(expiresAt).getTime() > Date.now());
  if (live) {
    return {
      status: "premium",
      valid_until: expiresAt === null ? null : new Date(expiresAt).toISOString(),
      tier: "premium",
    };
  }
  if (status === "expired" ||
    (expiresAt !== null && new Date(expiresAt).getTime() <= Date.now())) {
    return {
      status: "expired",
      valid_until: expiresAt === null ? null : new Date(expiresAt).toISOString(),
      tier: "free",
    };
  }
  return { status: "free", valid_until: null, tier: "free" };
}

/**
 * input_hash = lowercase SHA-256 of the UTF-8 bytes of canonicalJSON({capability, source}), reusing
 * recipe-draft-sessions/canonicalJSON.ts (object keys sorted, array order unchanged). It is immutable
 * across reserve -> commit -> finalize and is NOT the approved payload hash.
 */
export function computeInputHash(
  capability: string,
  source: Record<string, unknown>,
): Promise<string> {
  return canonicalHash({ capability, source });
}

/**
 * smart_import approved payload: the selected candidate object for a multi-candidate job, or the whole
 * top-level result for a single-result job whose candidate id is the reserved literal "primary".
 * Returns null when the candidate is not a member of the owned job result (fail-closed).
 */
export function extractImportPayload(
  result: Record<string, unknown> | null,
  candidateID: string,
): Record<string, unknown> | null {
  if (!result || typeof result !== "object" || Array.isArray(result)) return null;
  const candidates = result.candidate_recipes;
  // A multi-result job carries a non-empty candidate_recipes array; only its exact members are valid.
  // `primary` is reserved for the single-result shape (candidate_recipes absent OR empty []).
  if (Array.isArray(candidates) && candidates.length > 0) {
    const match = candidates.find(
      (candidate) =>
        candidate !== null && typeof candidate === "object" &&
        !Array.isArray(candidate) &&
        (candidate as Record<string, unknown>).candidate_id === candidateID,
    );
    return (match as Record<string, unknown>) ?? null;
  }
  if (candidateID === "primary") return result;
  return null;
}

/**
 * ai_edit approved payload: an immutable snapshot derived from the persisted turn (context_snapshot +
 * result) and the accepted approval (selected_paths + applied_revision). The draft approval `receipt`
 * is coordination metadata (request/turn/action/session ids), not the recipe; it is never persisted as
 * the recoverable recipe. Final apply of selected_paths to produce the saveable recipe fields is the
 * DEV-428 draft-composition contract; until it freezes, this immutable snapshot is the durable payload.
 */
export function extractEditPayload(
  approval: Record<string, unknown> | null,
  turn: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!approval || typeof approval !== "object" || Array.isArray(approval)) return null;
  if (!turn || typeof turn !== "object" || Array.isArray(turn)) return null;
  const contextSnapshot = turn.context_snapshot;
  const result = turn.result;
  if (!contextSnapshot || typeof contextSnapshot !== "object" || Array.isArray(contextSnapshot)) {
    return null;
  }
  if (!result || typeof result !== "object" || Array.isArray(result)) return null;
  if (!Array.isArray(approval.selected_paths)) return null;
  const appliedRevision = approval.applied_revision;
  if (appliedRevision === null || appliedRevision === undefined) return null;
  return {
    context_snapshot: contextSnapshot as Record<string, unknown>,
    result: result as Record<string, unknown>,
    selected_paths: approval.selected_paths as string[],
    applied_revision: appliedRevision,
  };
}

/** Release stage from server configuration; freeTest is the dormant default. */
export function resolveStage(value: string | undefined): "freeTest" | "commercial" {
  return value === "commercial" ? "commercial" : "freeTest";
}
