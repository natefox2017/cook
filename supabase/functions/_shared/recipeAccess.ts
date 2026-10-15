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
  if (Array.isArray(candidates)) {
    const match = candidates.find(
      (candidate) =>
        candidate !== null && typeof candidate === "object" &&
        !Array.isArray(candidate) &&
        (candidate as Record<string, unknown>).candidate_id === candidateID,
    );
    return (match as Record<string, unknown>) ?? null;
  }
  // Single-result job: the reserved literal "primary" maps to the whole parsed recipe.
  if (candidateID === "primary") return result;
  return null;
}

/**
 * ai_edit approved payload: the durable approval receipt persisted by the draft stack. The receipt
 * binds the owner, session, turn and applied revision; finalize persists it as the recoverable payload.
 */
export function extractEditPayload(
  approval: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!approval || typeof approval !== "object" || Array.isArray(approval)) return null;
  const receipt = approval.receipt;
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) return null;
  return receipt as Record<string, unknown>;
}

/** Release stage from server configuration; freeTest is the dormant default. */
export function resolveStage(value: string | undefined): "freeTest" | "commercial" {
  return value === "commercial" ? "commercial" : "freeTest";
}
