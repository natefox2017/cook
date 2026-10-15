// Developer: gengyun
// Purpose: Map verified-owner commercial usage requests to durable ledger RPCs. It settles one unit per
// operation from the persisted job/proposal (never a client success flag) and freezes the frozen
// commercial error vocabulary. Pure handler; production adapters inject real Supabase reads and RPCs.

import {
  ackResponse,
  commitRequest,
  commitResponse,
  ERROR_STATUSES,
  finalizeRequest,
  finalizeResponse,
  reservation,
  reservationRequest,
  usageError,
} from "../_shared/recipeAccessContract.mjs";
import {
  computeInputHash,
  extractEditPayload,
  extractImportPayload,
  resolveStage,
} from "../_shared/recipeAccess.ts";
import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";
import { handleCors } from "../_shared/cors.ts";

type Row = Record<string, unknown>;

export interface Dependencies {
  verifiedOwner(
    request: Request,
  ): Promise<{ id: string; isAnonymous: boolean } | null>;
  isEnabled(): boolean | Promise<boolean>;
  /** Server-owned release stage (freeTest dormant default or commercial). */
  stage: "freeTest" | "commercial";
  loadOwnedJob(owner: string, job: string): Promise<Row | null>;
  loadOwnedSession(owner: string, session: string): Promise<Row | null>;
  loadOwnedTurn(owner: string, session: string, turn: string): Promise<Row | null>;
  loadOwnedApproval(
    owner: string,
    session: string,
    turn: string,
  ): Promise<Row | null>;
  rpc(name: string, args: Row): Promise<Row>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const RECOVERABLE: Record<string, boolean> = {
  AUTH_REQUIRED: true,
  OWNER_MISMATCH: false,
  NOT_FOUND: false,
  IDEMPOTENCY_CONFLICT: false,
  RESERVATION_EXPIRED: true,
  INVALID_INPUT: false,
  QUOTA_EXCEEDED: true,
  UPGRADE_REQUIRED: true,
  CONFIGURATION_UNAVAILABLE: true,
  SERVICE_UNAVAILABLE: true,
  INTERNAL_ERROR: true,
};
const MESSAGES: Record<string, string> = {
  AUTH_REQUIRED: "Sign in to use this feature.",
  OWNER_MISMATCH: "The operation belongs to a different account.",
  NOT_FOUND: "The operation was not found.",
  IDEMPOTENCY_CONFLICT: "This operation key was already used with different input.",
  RESERVATION_EXPIRED: "The reservation is no longer valid.",
  INVALID_INPUT: "The request is malformed.",
  QUOTA_EXCEEDED: "Usage quota reached.",
  UPGRADE_REQUIRED: "Premium is required for this capability.",
  CONFIGURATION_UNAVAILABLE: "Client and server stage configuration disagree.",
  SERVICE_UNAVAILABLE: "The commerce service is temporarily unavailable.",
  INTERNAL_ERROR: "An unexpected error occurred.",
};

export class Failure extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "Failure";
  }
}

function requireThat(condition: unknown, code: string): asserts condition {
  if (!condition) throw new Failure(code);
}

function uuid(value: unknown): string {
  requireThat(typeof value === "string" && UUID.test(value), "INVALID_INPUT");
  return value;
}

function json(
  body: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return Response.json(body, { status, headers });
}

function error(
  code: string,
  requestID: string,
  headers: HeadersInit = {},
): Response {
  const status = (ERROR_STATUSES as Record<string, number>)[code] ?? 500;
  const body = {
    code,
    message: MESSAGES[code] ?? MESSAGES.INTERNAL_ERROR,
    recoverable: RECOVERABLE[code] ?? true,
    request_id: requestID,
  };
  if (usageError(body) === null) {
    return json(
      {
        code: "INTERNAL_ERROR",
        message: MESSAGES.INTERNAL_ERROR,
        recoverable: true,
        request_id: requestID,
      },
      500,
    );
  }
  return json(body, status, headers);
}

function retryAfterSeconds(until: unknown): string | null {
  if (typeof until !== "string") return null;
  const ms = new Date(until).getTime() - Date.now();
  if (!Number.isFinite(ms)) return null;
  return String(Math.max(0, Math.ceil(ms / 1000)));
}

function rpcRow(value: unknown, code = "INTERNAL_ERROR"): Row {
  requireThat(
    value !== null && typeof value === "object" && !Array.isArray(value),
    code,
  );
  return value as Row;
}

/**
 * Load + validate the persisted origin for a usage operation. "reserve" accepts the persisted pending
 * source (before generation); "settle" (commit/finalize) requires trusted durable success: a completed
 * import job with a member candidate, or an accepted AI-edit approval. Only settle returns the payload.
 */
async function loadSource(
  deps: Dependencies,
  owner: string,
  capability: string,
  source: Row,
  mode: "reserve" | "settle",
): Promise<Row | null> {
  if (capability === "smart_import" && source.origin === "import_job") {
    const job = await deps.loadOwnedJob(owner, uuid(source.job_id));
    requireThat(job !== null, "NOT_FOUND");
    requireThat(job.status === "completed", "INVALID_INPUT");
    const candidate = (source.candidate_ids as string[])[0];
    const payload = extractImportPayload(job.result as Row | null, candidate);
    requireThat(payload !== null, "INVALID_INPUT");
    return payload;
  }
  if (capability === "ai_edit" && source.origin === "draft_approval") {
    const session = await deps.loadOwnedSession(owner, uuid(source.session_id));
    requireThat(session !== null, "NOT_FOUND");
    const turn = await deps.loadOwnedTurn(
      owner,
      uuid(source.session_id),
      uuid(source.turn_request_id),
    );
    requireThat(turn !== null, "NOT_FOUND");
    if (mode === "reserve") {
      // The pending turn is the persisted source before provider generation.
      return null;
    }
    const approval = await deps.loadOwnedApproval(
      owner,
      uuid(source.session_id),
      uuid(source.turn_request_id),
    );
    requireThat(approval !== null, "NOT_FOUND");
    requireThat(approval.action === "accept", "INVALID_INPUT");
    const payload = extractEditPayload(approval, turn);
    requireThat(payload !== null, "INVALID_INPUT");
    return payload;
  }
  throw new Failure("INVALID_INPUT");
}

/** Recompute the canonical input_hash and reject any client-provided hash that does not match it. */
async function verifyInputHash(
  capability: string,
  inputHash: unknown,
  source: Row,
): Promise<string> {
  requireThat(typeof inputHash === "string", "INVALID_INPUT");
  const expected = await computeInputHash(capability, source);
  requireThat(inputHash === expected, "INVALID_INPUT");
  return expected;
}

export async function handleRequest(
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  const preflight = handleCors(request);
  if (preflight) return preflight;
  const requestID = crypto.randomUUID();
  try {
    requireThat(
      request.method === "POST",
      "INVALID_INPUT",
    );
    requireThat(
      /^Bearer\s+\S+$/i.test(request.headers.get("authorization") ?? ""),
      "AUTH_REQUIRED",
    );
    const auth = await deps.verifiedOwner(request);
    requireThat(
      auth !== null && typeof auth.id === "string" && UUID.test(auth.id) &&
        auth.isAnonymous === false,
      "AUTH_REQUIRED",
    );
    const owner = auth.id;
    requireThat(await deps.isEnabled() === true, "SERVICE_UNAVAILABLE");
    // Fail closed on a client/server release-stage disagreement. The client stage is only ever compared,
    // never trusted to grant entitlement.
    const clientStage = request.headers.get("x-recipe-pals-stage");
    if (clientStage !== null && resolveStage(clientStage) !== deps.stage) {
      return error("CONFIGURATION_UNAVAILABLE", requestID);
    }

    const segments = new URL(request.url).pathname.split("/").filter(Boolean);
    const base = segments.lastIndexOf("recipe-usage");
    requireThat(base >= 0, "NOT_FOUND");
    const tail = segments.slice(base + 1);

    let action = "";
    let operationID = "";
    if (tail.length === 1 && tail[0] === "reservations") {
      action = "reserve";
    } else if (tail.length === 2 && UUID.test(tail[0]) &&
      (tail[1] === "commit" || tail[1] === "release" ||
        tail[1] === "finalize" || tail[1] === "ack")) {
      operationID = tail[0];
      action = tail[1];
    }
    requireThat(action !== "", "NOT_FOUND");

    let body: Row = {};
    if (action === "reserve" || action === "commit" || action === "finalize") {
      body = await request.json().catch(() => null);
      requireThat(body !== null && typeof body === "object", "INVALID_INPUT");
    }

    if (action === "reserve") {
      const req = reservationRequest(body);
      requireThat(req !== null, "INVALID_INPUT");
      const hash = await verifyInputHash(req.capability, req.input_hash, req.source);
      await loadSource(deps, owner, req.capability, req.source, "reserve");
      const out = rpcRow(
        await deps.rpc("recipe_usage_reserve", {
          p_owner_id: owner,
          p_operation_id: req.operation_id,
          p_capability: req.capability,
          p_input_hash: hash,
          p_source: req.source,
        }),
      );
      requireThat(
        out.code === "RESERVED" || out.code === "REPLAY" ||
          out.code === "NOT_FOUND" || out.code === "IDEMPOTENCY_CONFLICT" ||
          out.code === "QUOTA_EXCEEDED" || out.code === "INVALID_INPUT",
        "INTERNAL_ERROR",
      );
      if (out.code === "NOT_FOUND") return error("NOT_FOUND", requestID);
      if (out.code === "IDEMPOTENCY_CONFLICT") return error("IDEMPOTENCY_CONFLICT", requestID);
      if (out.code === "QUOTA_EXCEEDED") {
        return error("QUOTA_EXCEEDED", requestID, {
          "Retry-After": retryAfterSeconds(out.reset_at) ?? "0",
        });
      }
      if (out.code === "INVALID_INPUT") return error("INVALID_INPUT", requestID);
      const res = reservation(out.reservation);
      requireThat(res !== null, "INTERNAL_ERROR");
      return json(res, out.code === "RESERVED" ? 201 : 200);
    }

    if (action === "commit") {
      const req = commitRequest(body);
      requireThat(req !== null, "INVALID_INPUT");
      const hash = await verifyInputHash(req.capability, req.input_hash, req.source);
      await loadSource(deps, owner, req.capability, req.source, "settle");
      const out = rpcRow(
        await deps.rpc("recipe_usage_commit", {
          p_owner_id: owner,
          p_operation_id: operationID,
          p_capability: req.capability,
          p_input_hash: hash,
        }),
      );
      requireThat(
        out.code === "COMMITTED" || out.code === "NOT_FOUND" ||
          out.code === "IDEMPOTENCY_CONFLICT" || out.code === "RESERVATION_EXPIRED",
        "INTERNAL_ERROR",
      );
      if (out.code === "NOT_FOUND") return error("NOT_FOUND", requestID);
      if (out.code === "IDEMPOTENCY_CONFLICT") return error("IDEMPOTENCY_CONFLICT", requestID);
      if (out.code === "RESERVATION_EXPIRED") return error("RESERVATION_EXPIRED", requestID, { "Retry-After": "0" });
      const res = commitResponse({
        operation_id: out.operation_id,
        status: "committed",
        committed_units: 1,
        period_start: out.period_start,
      });
      requireThat(res !== null, "INTERNAL_ERROR");
      return json(res);
    }

    if (action === "release") {
      const out = rpcRow(
        await deps.rpc("recipe_usage_release", {
          p_owner_id: owner,
          p_operation_id: operationID,
        }),
      );
      requireThat(
        out.code === "RELEASED" || out.code === "COMMITTED" ||
          out.code === "NOT_FOUND" || out.code === "RESERVATION_EXPIRED",
        "INTERNAL_ERROR",
      );
      if (out.code === "NOT_FOUND") return error("NOT_FOUND", requestID);
      if (out.code === "RESERVATION_EXPIRED") return error("RESERVATION_EXPIRED", requestID, { "Retry-After": "0" });
      const res = reservation(out.reservation);
      requireThat(res !== null, "INTERNAL_ERROR");
      return json(res);
    }

    if (action === "finalize") {
      const req = finalizeRequest(body);
      requireThat(req !== null, "INVALID_INPUT");
      const hash = await verifyInputHash(req.capability, req.input_hash, req.source);
      const payload = await loadSource(deps, owner, req.capability, req.source, "settle");
      const payloadHash = await canonicalHash(payload);
      const out = rpcRow(
        await deps.rpc("recipe_usage_finalize", {
          p_owner_id: owner,
          p_operation_id: operationID,
          p_capability: req.capability,
          p_input_hash: hash,
          p_source: req.source,
          p_payload_hash: payloadHash,
          p_payload: payload,
        }),
      );
      requireThat(
        out.code === "FINALIZED" || out.code === "NOT_FOUND" ||
          out.code === "IDEMPOTENCY_CONFLICT" || out.code === "RESERVATION_EXPIRED",
        "INTERNAL_ERROR",
      );
      if (out.code === "NOT_FOUND") return error("NOT_FOUND", requestID);
      if (out.code === "IDEMPOTENCY_CONFLICT") return error("IDEMPOTENCY_CONFLICT", requestID);
      if (out.code === "RESERVATION_EXPIRED") return error("RESERVATION_EXPIRED", requestID, { "Retry-After": "0" });
      const res = finalizeResponse({
        operation_id: out.operation_id,
        status: "finalized",
        recipe_id: out.recipe_id,
        payload_hash: out.payload_hash,
        committed_units: 1,
        period_start: out.period_start,
      });
      requireThat(res !== null, "INTERNAL_ERROR");
      return json(res);
    }

    if (action === "ack") {
      const out = rpcRow(
        await deps.rpc("recipe_usage_ack", {
          p_owner_id: owner,
          p_operation_id: operationID,
        }),
      );
      requireThat(
        out.code === "ACKED" || out.code === "NOT_FOUND" ||
          out.code === "RESERVATION_EXPIRED",
        "INTERNAL_ERROR",
      );
      if (out.code === "NOT_FOUND") return error("NOT_FOUND", requestID);
      if (out.code === "RESERVATION_EXPIRED") return error("RESERVATION_EXPIRED", requestID, { "Retry-After": "0" });
      const res = ackResponse({ operation_id: out.operation_id, status: "acked" });
      requireThat(res !== null, "INTERNAL_ERROR");
      return json(res);
    }

    return error("NOT_FOUND", requestID);
  } catch (err) {
    if (err instanceof Failure) return error(err.code, requestID);
    if (err instanceof SyntaxError) return error("INVALID_INPUT", requestID);
    console.error("recipe_usage_unhandled");
    return error("INTERNAL_ERROR", requestID);
  }
}
