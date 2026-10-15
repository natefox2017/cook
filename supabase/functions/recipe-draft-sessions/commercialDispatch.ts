// Developer: gengyun
// Purpose: Bind the verified draft dispatch worker to the DEV-427 ai_edit usage ledger. The worker
//          stays pure; this module injects reserve/fence/mark-generated hooks over the stable
//          operation_id = turn request_id and returns the persisted turn for the owner handler.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { createAIDraftDispatchWorker } from "../recipe-import-worker/aiDraftDispatch.ts";
import { createAIDraftSafeTransport } from "../recipe-import-worker/aiDraftSafeTransport.ts";
import { computeInputHash } from "../_shared/recipeAccess.ts";

type Row = Record<string, unknown>;
type WorkerOptions = Parameters<typeof createAIDraftDispatchWorker>[0];
type WorkerDependencies = Pick<
  WorkerOptions,
  "storage" | "loadRouteConfiguration" | "resolveSecret"
>;

interface DispatcherOptions {
  enabled: boolean;
  admin: SupabaseClient;
  workerDependencies: WorkerDependencies;
  loadOwnedTurn: (
    owner: string,
    session: string,
    turn: string,
  ) => Promise<unknown>;
}

/** The frozen ai_edit source: operation_id equals turn_request_id equals the turn request_id. */
function sourceFor(sessionID: string, turnRequestID: string): Row {
  return {
    origin: "draft_approval",
    job_id: null,
    candidate_ids: null,
    session_id: sessionID,
    turn_request_id: turnRequestID,
  };
}

function rpcRow(out: { data: unknown; error: unknown } | null): Row {
  if (!out || out.error) {
    throw new Error("DRAFT_UNIT_RPC_FAILED");
  }
  return (out.data ?? {}) as Row;
}

export function createCommercialDraftDispatcher(options: DispatcherOptions) {
  const { enabled, admin, workerDependencies, loadOwnedTurn } = options;
  const safeTransport = createAIDraftSafeTransport({ enabled: true });

  const reserveUnit = async (
    ownerID: string,
    sessionID: string,
    requestID: string,
  ) => {
    const source = sourceFor(sessionID, requestID);
    const inputHash = await computeInputHash("ai_edit", source);
    const row = rpcRow(await admin.rpc("recipe_usage_reserve", {
      p_owner_id: ownerID,
      p_operation_id: requestID,
      p_capability: "ai_edit",
      p_input_hash: inputHash,
      p_source: source,
    }));
    if (row.code !== "RESERVED" && row.code !== "REPLAY") {
      throw new Error(`DRAFT_UNIT_RESERVE_${row.code ?? "UNKNOWN"}`);
    }
  };

  const fenceUnitDispatched = async (
    ownerID: string,
    _sessionID: string,
    requestID: string,
  ) => {
    const row = rpcRow(await admin.rpc("recipe_usage_mark_dispatched", {
      p_owner_id: ownerID,
      p_operation_id: requestID,
    }));
    if (row.code !== "DISPATCHED") {
      throw new Error(`DRAFT_UNIT_FENCE_${row.code ?? "UNKNOWN"}`);
    }
  };

  const markUnitGenerated = async (
    ownerID: string,
    _sessionID: string,
    requestID: string,
  ) => {
    const row = rpcRow(await admin.rpc("recipe_usage_mark_generated", {
      p_owner_id: ownerID,
      p_operation_id: requestID,
    }));
    if (row.code !== "GENERATED") {
      throw new Error(`DRAFT_UNIT_GENERATED_${row.code ?? "UNKNOWN"}`);
    }
  };

  const worker = createAIDraftDispatchWorker({
    enabled,
    ...workerDependencies,
    safeTransport,
    reserveUnit,
    fenceUnitDispatched,
    markUnitGenerated,
  });

  return {
    /** Run one durable dispatch attempt and return the persisted turn (pending or terminal). */
    async dispatchTurn(
      ownerID: string,
      sessionID: string,
      requestID: string,
    ): Promise<unknown> {
      await worker.runTurn({ ownerID, sessionID, requestID });
      return loadOwnedTurn(ownerID, sessionID, requestID);
    },
  };
}
