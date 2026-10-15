// Developer: gengyun
// Purpose: Map verified-owner recipe translation requests through the phase-II internal metering RPCs
//          to the safe provider and return the reviewable structured proposal. It is closed-by-default:
//          the commercial stage, a premium entitlement and the 20/month quota are enforced by the
//          internal reserve before any provider side effect, the stored source revision is re-checked,
//          and the provider output is deterministically validated (stable mapping + numeric preservation)
//          before finalize.

import {
  buildPrompt,
  DEADLINE_MS,
  MAX_INPUT_BYTES,
  MAX_OUTPUT_BYTES,
  parseRequest,
  TranslationContractError,
  validateProviderOutput,
  type TranslationProposal,
} from "./contract.ts";
import { handleCors } from "../_shared/cors.ts";
import { readBoundedJSONObject } from "../_shared/bounded-json.ts";
import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";
import {
  computeInternalInputHash,
  internalSourceForTranslation,
  type InternalCapability,
  type InternalSource,
  type InternalUsageResult,
} from "../_shared/recipeInternalUsage.ts";

type Row = Record<string, unknown>;

export interface Dependencies {
  verifiedOwner(
    request: Request,
  ): Promise<{ id: string; isAnonymous: boolean } | null>;
  isEnabled(): boolean | Promise<boolean>;
  /** Server-owned release stage; freeTest is the dormant default and never reaches the provider. */
  stage: "freeTest" | "commercial";
  /** Loads the owner's canonical recipe id + per-recipe updatedAt from the user_snapshots payload. */
  loadOwnedRecipe(owner: string, recipeID: string): Promise<Row | null>;
  /** Loads the persisted finalized translation proposal for a committed reservation (idempotent replay). */
  loadFinalizedResult(
    owner: string,
    capability: InternalCapability,
    inputHash: string,
  ): Promise<Row | null>;
  /** The independent bounded provider (throws a distinct error per failure mode). */
  translate(prompt: string, signal: AbortSignal): Promise<unknown>;
  reserve(
    owner: string,
    operationID: string,
    capability: InternalCapability,
    inputHash: string,
    source: InternalSource,
  ): Promise<InternalUsageResult>;
  markDispatched(owner: string, operationID: string): Promise<InternalUsageResult>;
  finalize(
    owner: string,
    operationID: string,
    capability: InternalCapability,
    inputHash: string,
    source: InternalSource,
    payloadHash: string,
    payload: Row,
    resultID: string,
  ): Promise<InternalUsageResult>;
  release(owner: string, operationID: string): Promise<InternalUsageResult>;
}

const CAPABILITY: InternalCapability = "recipe_translation";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const statuses: Record<string, number> = {
  AUTH_REQUIRED: 401,
  UPGRADE_REQUIRED: 402,
  NOT_FOUND: 404,
  STALE_REVISION: 409,
  INVALID_INPUT: 422,
  QUOTA_EXCEEDED: 429,
  PROVIDER_UNAVAILABLE: 503,
  TRANSLATION_DISABLED: 503,
  INTERNAL_ERROR: 500,
};
const recoverable: Record<string, boolean> = {
  AUTH_REQUIRED: true,
  UPGRADE_REQUIRED: true,
  NOT_FOUND: false,
  STALE_REVISION: true,
  INVALID_INPUT: false,
  QUOTA_EXCEEDED: true,
  PROVIDER_UNAVAILABLE: true,
  TRANSLATION_DISABLED: true,
  INTERNAL_ERROR: true,
};
const messages: Record<string, string> = {
  AUTH_REQUIRED: "Sign in to translate this recipe.",
  UPGRADE_REQUIRED: "Premium is required to translate recipes.",
  NOT_FOUND: "The recipe was not found.",
  STALE_REVISION: "The recipe changed since it was opened. Refresh and try again.",
  INVALID_INPUT: "The translation request is malformed.",
  QUOTA_EXCEEDED: "Monthly translation quota reached.",
  PROVIDER_UNAVAILABLE: "The translation service is temporarily unavailable.",
  TRANSLATION_DISABLED: "Recipe translation is not available.",
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

function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return Response.json(body, { status, headers });
}

function error(code: string, requestID: string): Response {
  return json(
    {
      code,
      message: messages[code] ?? messages.INTERNAL_ERROR,
      recoverable: recoverable[code] ?? true,
      request_id: requestID,
    },
    statuses[code] ?? 500,
  );
}

/** The stored recipe timestamp canonicalized to the same millisecond UTC form as the wire revision. */
function storedRevision(value: unknown): string {
  requireThat(typeof value === "string", "INTERNAL_ERROR");
  const parsed = new Date(value);
  requireThat(Number.isFinite(parsed.getTime()), "INTERNAL_ERROR");
  return parsed.toISOString();
}

function rpcResult(value: InternalUsageResult, code: string): Row {
  requireThat(
    value !== null && typeof value === "object" && !Array.isArray(value),
    code,
  );
  return value as Row;
}

function retryAfterSeconds(until: unknown): string {
  if (typeof until !== "string") return "0";
  const ms = new Date(until).getTime() - Date.now();
  if (!Number.isFinite(ms)) return "0";
  return String(Math.max(0, Math.ceil(ms / 1000)));
}

/** Definite provider failures happened before any provider side effect; the unit is released. */
function isDefiniteProviderFailure(message: string): boolean {
  return message === "TRANSLATION_PROVIDER_DISABLED" ||
    message === "TRANSLATION_PROVIDER_INPUT" ||
    message === "TRANSLATION_PROVIDER_INPUT_BUDGET" ||
    message === "TRANSLATION_PROVIDER_SECRET";
}

export async function handleRequest(
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  const preflight = handleCors(request);
  if (preflight) return preflight;
  const requestID = crypto.randomUUID();
  try {
    requireThat(request.method === "POST", "INVALID_INPUT");
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
    requireThat(await deps.isEnabled() === true, "TRANSLATION_DISABLED");
    // Closed-by-default: the provider is unreachable in the dormant freeTest stage.
    requireThat(deps.stage === "commercial", "TRANSLATION_DISABLED");

    const body = await readBoundedJSONObject(request, MAX_INPUT_BYTES);
    const parsed = parseRequest(body);

    // Ownership + stored-revision fence. A recipe edited on another device since the client loaded
    // it has a different updated_at and is rejected before any metering or provider side effect.
    const owned = await deps.loadOwnedRecipe(owner, parsed.recipe_id);
    requireThat(owned !== null, "NOT_FOUND");
    requireThat(
      storedRevision(owned.updatedAt) === parsed.expected_revision,
      "STALE_REVISION",
    );

    // Metering identity: the internal source binds the client-stable proposal id; the server computes
    // the hash and the reservation is keyed by that id so a retry replays instead of double-charging.
    const internalSource = internalSourceForTranslation(parsed.proposal_id);
    const inputHash = await computeInternalInputHash(CAPABILITY, internalSource);

    const reservation = rpcResult(
      await deps.reserve(
        owner,
        parsed.proposal_id,
        CAPABILITY,
        inputHash,
        internalSource,
      ),
      "INTERNAL_ERROR",
    );
    if (reservation.code === "UPGRADE_REQUIRED") {
      return error("UPGRADE_REQUIRED", requestID);
    }
    if (reservation.code === "QUOTA_EXCEEDED") {
      return json(
        {
          code: "QUOTA_EXCEEDED",
          message: messages.QUOTA_EXCEEDED,
          recoverable: true,
          request_id: requestID,
          reset_at: reservation.reset_at ?? null,
        },
        429,
        { "Retry-After": retryAfterSeconds(reservation.reset_at) },
      );
    }
    if (reservation.code === "NOT_FOUND") return error("NOT_FOUND", requestID);
    if (reservation.code === "IDEMPOTENCY_CONFLICT") {
      return error("INVALID_INPUT", requestID);
    }
    requireThat(
      reservation.code === "RESERVED" || reservation.code === "REPLAY",
      "INTERNAL_ERROR",
    );

    // Dispatch fence: a prior dispatched attempt left the unit dispatched_unknown, so re-call the
    // provider directly instead of re-marking. A committed reservation replays the stored durable
    // outcome without a second charge; released/expired reservations without a re-servable proposal
    // fail closed.
    const nested = reservation.reservation;
    const reservationStatus =
      nested !== null && typeof nested === "object" && !Array.isArray(nested)
        ? (nested as Row).status
        : "reserved";
    if (reservationStatus === "dispatched_unknown") {
      // Already fenced; the held unit is still accounted, so re-call the provider directly.
    } else if (reservationStatus === "reserved") {
      const dispatched = rpcResult(
        await deps.markDispatched(owner, parsed.proposal_id),
        "INTERNAL_ERROR",
      );
      requireThat(
        dispatched.code === "DISPATCHED" ||
          dispatched.code === "RESERVATION_EXPIRED",
        "INTERNAL_ERROR",
      );
      if (dispatched.code === "RESERVATION_EXPIRED") {
        return error("PROVIDER_UNAVAILABLE", requestID);
      }
    } else if (reservationStatus === "committed") {
      // Recover the already-finalized proposal and return it verbatim without a second charge or
      // a provider side effect. Committed is set atomically with the finalization insert, so the
      // durable payload must exist; a missing row is an internal inconsistency.
      const stored = await deps.loadFinalizedResult(owner, CAPABILITY, inputHash);
      requireThat(stored !== null, "INTERNAL_ERROR");
      return json(stored);
    } else {
      return error("PROVIDER_UNAVAILABLE", requestID);
    }

    let proposal: TranslationProposal;
    try {
      const raw = await deps.translate(
        buildPrompt(parsed),
        AbortSignal.timeout(DEADLINE_MS),
      );
      proposal = validateProviderOutput(raw, parsed);
    } catch (err) {
      // Provider output is unusable (numeric/structural fabrication or transport failure):
      // the held unit is released and the request fails before any finalize.
      await deps.release(owner, parsed.proposal_id);
      if (err instanceof TranslationContractError) {
        return error("PROVIDER_UNAVAILABLE", requestID);
      }
      return error("PROVIDER_UNAVAILABLE", requestID);
    }

    if (JSON.stringify(proposal).length > MAX_OUTPUT_BYTES) {
      await deps.release(owner, parsed.proposal_id);
      return error("PROVIDER_UNAVAILABLE", requestID);
    }

    const payloadHash = await canonicalHash(proposal);
    const final = rpcResult(
      await deps.finalize(
        owner,
        parsed.proposal_id,
        CAPABILITY,
        inputHash,
        internalSource,
        payloadHash,
        proposal as unknown as Row,
        parsed.proposal_id,
      ),
      "INTERNAL_ERROR",
    );
    requireThat(
      final.code === "FINALIZED" || final.code === "RESERVATION_EXPIRED",
      "INTERNAL_ERROR",
    );
    if (final.code === "RESERVATION_EXPIRED") {
      return error("PROVIDER_UNAVAILABLE", requestID);
    }
    return json(proposal);
  } catch (err) {
    if (err instanceof Failure) return error(err.code, requestID);
    if (err instanceof TranslationContractError) {
      return error("INVALID_INPUT", requestID);
    }
    if (err instanceof SyntaxError) return error("INVALID_INPUT", requestID);
    console.error("recipe_translation_unhandled");
    return error("INTERNAL_ERROR", requestID);
  }
}
