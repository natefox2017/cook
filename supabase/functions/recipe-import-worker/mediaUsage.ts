// Developer: gengyun
// Purpose: DEV-78 media-import metering at the user-selected save callsite. One
//          bounded adapter atomically reserves the media_import quota plus one
//          smart_import unit per selected candidate in a single transaction via
//          the additive bundle RPC, then settles/releases per capability.

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

export interface MediaBundleCandidate {
  candidate_id: string;
  input_hash: string;
  source: SmartImportSource;
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
      reservedCandidates: number;
    }
  | { code: MediaBundleBlockedCode | "MEDIA_BUNDLE_BLOCKED"; message: string };

function blockedCode(message: string): MediaBundleBlockedCode | "MEDIA_BUNDLE_BLOCKED" {
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

/**
 * Atomically reserve the media_import unit plus one smart_import unit per
 * selected candidate under one media import operation. The bundle RPC raises
 * on any block, so the whole transaction rolls back and no partial reservation
 * survives. Stable child operation ids are derived server-side (md5).
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
    const inputHash = await canonicalHash({
      capability: "smart_import",
      source,
    });
    candidates.push({
      candidate_id: candidateID,
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
    return {
      code,
      operationId: String(raw.operation_id ?? jobID),
      reservedCandidates: Number(raw.reserved_candidates ?? candidateIDs.length),
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
