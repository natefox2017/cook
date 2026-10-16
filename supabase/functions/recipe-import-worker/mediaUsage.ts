// Developer: gengyun
// Purpose: DEV-78 media-import metering at the user-selected save callsite. One
//          bounded adapter atomically reserves the media_import quota plus one
//          smart_import unit per selected candidate in a single transaction via
//          the additive bundle RPC, using the frozen DEV-430 stable operation id,
//          then settles/releases per capability.

import {
  computeInternalInputHash,
  finalizeInternal,
  internalSourceForMediaImport,
  releaseInternal,
  type InternalUsageRPC,
  type InternalUsageResult,
} from "../_shared/recipeInternalUsage.ts";
import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";

type RPCInvoke = (
  name: string,
  args: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: unknown }>;

/** Adapt a Supabase service client rpc() to the typed internal usage port. */
export function createLedgerRPC(invoke: RPCInvoke): InternalUsageRPC {
  return async (name, args) => {
    const { data, error } = await invoke(name, args);
    if (error) {
      throw new Error("The metering service is unavailable.");
    }
    return (data as Record<string, unknown>) ?? {};
  };
}

export interface SmartImportSource {
  origin: "import_job";
  job_id: string;
  candidate_ids: [string];
  session_id: null;
  turn_request_id: null;
}

interface MediaBundleCandidate {
  candidate_id: string;
  operation_id: string;
  input_hash: string;
  source: SmartImportSource;
}

export interface ReservationRef {
  candidate_id?: string;
  operation_id: string;
  owner_id: string;
  capability: string;
  period_start: string | null;
  policy_version: number;
  tier_at_reserve: string;
  reserved_units: number;
  status: string;
  reserved_until: string;
}

export type MediaBundleBlockedCode =
  | "UPGRADE_REQUIRED"
  | "QUOTA_EXCEEDED"
  | "IDEMPOTENCY_CONFLICT"
  | "NOT_FOUND"
  | "INVALID_INPUT";

export type ReserveMediaBundleResult =
  | {
      code: "RESERVED" | "REPLAY";
      operationId: string;
      media: ReservationRef;
      candidates: ReservationRef[];
    }
  | { code: MediaBundleBlockedCode | "MEDIA_BUNDLE_BLOCKED"; message: string };

/**
 * Frozen DEV-430 stable operation id: SHA-256 of `lowercase owner:job:candidate`,
 * first 16 bytes formatted as a UUID. Deterministic across retries so a replay
 * derives the same operation id and the existing reserve returns REPLAY.
 */
async function stableCandidateOperationID(
  ownerID: string,
  jobID: string,
  candidateID: string,
): Promise<string> {
  const input = `${ownerID.toLowerCase()}:${jobID.toLowerCase()}:${candidateID}`;
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input)),
  );
  const hex = Array.from(
    digest.slice(0, 16),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function blockedCode(
  message: string,
): MediaBundleBlockedCode | "MEDIA_BUNDLE_BLOCKED" {
  const match = /MEDIA_BUNDLE_BLOCKED:(\w+)/.exec(message);
  if (!match) return "MEDIA_BUNDLE_BLOCKED";
  const code = match[1];
  return (
    code === "UPGRADE_REQUIRED" ||
    code === "QUOTA_EXCEEDED" ||
    code === "IDEMPOTENCY_CONFLICT" ||
    code === "NOT_FOUND" ||
    code === "INVALID_INPUT"
  )
    ? code
    : "MEDIA_BUNDLE_BLOCKED";
}

function isBlockedCode(value: string): value is MediaBundleBlockedCode {
  return (
    value === "UPGRADE_REQUIRED" ||
    value === "QUOTA_EXCEEDED" ||
    value === "IDEMPOTENCY_CONFLICT" ||
    value === "NOT_FOUND" ||
    value === "INVALID_INPUT"
  );
}

function asReservation(value: unknown): ReservationRef {
  const row: Record<string, unknown> = value !== null &&
    typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
  const candidateID = typeof row.candidate_id === "string"
    ? row.candidate_id
    : undefined;
  return {
    ...(candidateID === undefined ? {} : { candidate_id: candidateID }),
    operation_id: typeof row.operation_id === "string" ? row.operation_id : "",
    owner_id: typeof row.owner_id === "string" ? row.owner_id : "",
    capability: typeof row.capability === "string" ? row.capability : "",
    period_start: typeof row.period_start === "string" ? row.period_start : null,
    policy_version: typeof row.policy_version === "number" ? row.policy_version : 0,
    tier_at_reserve: typeof row.tier_at_reserve === "string" ? row.tier_at_reserve : "",
    reserved_units: typeof row.reserved_units === "number" ? row.reserved_units : 0,
    status: typeof row.status === "string" ? row.status : "",
    reserved_until: typeof row.reserved_until === "string" ? row.reserved_until : "",
  };
}

/**
 * Atomically reserve the media_import unit plus one smart_import unit per
 * selected candidate under one media import operation. The bundle RPC raises on
 * any block, so the whole transaction rolls back and no partial reservation
 * survives. Stable candidate operation ids follow the frozen DEV-430
 * stableOperationID (SHA-256), never md5.
 */
export async function reserveMediaBundle(
  rpc: InternalUsageRPC,
  ownerID: string,
  jobID: string,
  candidateIDs: readonly string[],
): Promise<ReserveMediaBundleResult> {
  const mediaSource = internalSourceForMediaImport(jobID);
  const mediaHash = await computeInternalInputHash("media_import", mediaSource);
  const candidates: MediaBundleCandidate[] = [];
  for (const candidateID of candidateIDs) {
    const source: SmartImportSource = {
      origin: "import_job",
      job_id: jobID,
      candidate_ids: [candidateID],
      session_id: null,
      turn_request_id: null,
    };
    const inputHash = await canonicalHash({ capability: "smart_import", source });
    const operationID = await stableCandidateOperationID(
      ownerID,
      jobID,
      candidateID,
    );
    candidates.push({
      candidate_id: candidateID,
      operation_id: operationID,
      input_hash: inputHash,
      source,
    });
  }

  let raw: Record<string, unknown>;
  try {
    raw = await rpc("recipe_usage_reserve_media_bundle", {
      p_owner_id: ownerID,
      p_job_id: jobID,
      p_media_source: mediaSource,
      p_media_input_hash: mediaHash,
      p_candidates: candidates,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown";
    return { code: blockedCode(message), message };
  }

  const code = raw.code;
  if (code === "RESERVED" || code === "REPLAY") {
    const candidateRows = Array.isArray(raw.candidates) ? raw.candidates : [];
    return {
      code,
      operationId: String(raw.operation_id ?? jobID),
      media: asReservation(raw.media),
      candidates: candidateRows.map(asReservation),
    };
  }
  const fallback = String(code ?? "INVALID_INPUT");
  return {
    code: isBlockedCode(fallback) ? fallback : "INVALID_INPUT",
    message: "The media bundle reservation was rejected.",
  };
}

/** Settle the reserved media_import unit, binding the durable owned job as a media_task. */
export async function settleMediaImport(
  rpc: InternalUsageRPC,
  ownerID: string,
  mediaTaskID: string,
  payload: Record<string, unknown>,
): Promise<InternalUsageResult> {
  const source = internalSourceForMediaImport(mediaTaskID);
  const inputHash = await computeInternalInputHash("media_import", source);
  const payloadHash = await canonicalHash(payload);
  return await finalizeInternal(
    rpc,
    ownerID,
    mediaTaskID,
    "media_import",
    inputHash,
    source,
    null,
    payloadHash,
    payload,
    "media_task",
    mediaTaskID,
  );
}

/** Best-effort release of a media_import reservation that will not be settled. */
export async function releaseMediaImport(
  rpc: InternalUsageRPC,
  ownerID: string,
  mediaTaskID: string,
): Promise<void> {
  await releaseInternal(rpc, ownerID, mediaTaskID).catch(() => null);
}
