// Developer: gengyun
// Purpose: Worker-side media_import metering hook. Binds the persisted owned
//          import job as the media task identity (media_task_id = job id) and
//          settles exactly once against the DEV-427/438 phase-II ledger RPCs.

import {
  computeInternalInputHash,
  finalizeInternal,
  internalSourceForMediaImport,
  releaseInternal,
  reserveInternal,
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

async function sourceAndHash(mediaTaskID: string) {
  const source = internalSourceForMediaImport(mediaTaskID);
  const inputHash = await computeInternalInputHash("media_import", source);
  return { source, inputHash };
}

/** Reserve one media_import unit keyed by the durable owned import job id. */
export async function reserveMediaImport(
  rpc: InternalUsageRPC,
  ownerID: string,
  mediaTaskID: string,
): Promise<InternalUsageResult> {
  const { source, inputHash } = await sourceAndHash(mediaTaskID);
  return await reserveInternal(
    rpc,
    ownerID,
    mediaTaskID,
    "media_import",
    inputHash,
    source,
  );
}

/**
 * Map a reserve result to a user-facing completion block. RESERVED/REPLAY allow
 * work and return null; quota/entitlement/malformed results return a block that
 * never settles a success unit.
 */
export function mediaQuotaBlock(
  result: InternalUsageResult,
): { code: string; message: string } | null {
  if (result.code === "RESERVED" || result.code === "REPLAY") return null;
  if (result.code === "UPGRADE_REQUIRED") {
    return {
      code: result.code,
      message: "Media import requires a premium subscription.",
    };
  }
  if (result.code === "QUOTA_EXCEEDED") {
    return {
      code: result.code,
      message: "The monthly media import limit has been reached.",
    };
  }
  return {
    code: "MEDIA_QUOTA_UNAVAILABLE",
    message: "Media import quota is unavailable.",
  };
}

/** Settle the reservation once, binding the durable owned job as a media_task. */
export async function settleMediaImport(
  rpc: InternalUsageRPC,
  ownerID: string,
  mediaTaskID: string,
  payload: Record<string, unknown>,
): Promise<InternalUsageResult> {
  const { source, inputHash } = await sourceAndHash(mediaTaskID);
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

/** Best-effort release of a reservation that will not be settled. */
export async function releaseMediaImport(
  rpc: InternalUsageRPC,
  ownerID: string,
  mediaTaskID: string,
): Promise<void> {
  await releaseInternal(rpc, ownerID, mediaTaskID).catch(() => null);
}
