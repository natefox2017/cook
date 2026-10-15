// Developer: gengyun
// Purpose: Serve the server-owned commercial access snapshot for the authenticated owner. The owner,
// stage, policy_version and every quota number are server-owned; a client never authors them.

import { accessResponse, ERROR_STATUSES, usageError } from "../_shared/recipeAccessContract.mjs";
import { handleCors } from "../_shared/cors.ts";

type Row = Record<string, unknown>;

export interface Dependencies {
  verifiedOwner(
    request: Request,
  ): Promise<{ id: string; isAnonymous: boolean } | null>;
  policyVersion: number;
  stage: string;
  rpc(name: string, args: Row): Promise<Row>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export class Failure extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = "Failure";
  }
}

function requireThat(condition: unknown, code: string): asserts condition {
  if (!condition) throw new Failure(code);
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

function error(code: string, requestID: string): Response {
  const status = (ERROR_STATUSES as Record<string, number>)[code] ?? 500;
  const body = {
    code,
    message: code === "CONFIGURATION_UNAVAILABLE"
      ? "Client and server stage configuration disagree."
      : "The commerce service is temporarily unavailable.",
    recoverable: true,
    request_id: requestID,
  };
  if (usageError(body) === null) {
    return json(
      {
        code: "INTERNAL_ERROR",
        message: "An unexpected error occurred.",
        recoverable: true,
        request_id: requestID,
      },
      500,
    );
  }
  return json(body, status);
}

export async function handleRequest(
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  const preflight = handleCors(request);
  if (preflight) return preflight;
  const requestID = crypto.randomUUID();
  try {
    requireThat(request.method === "GET", "INTERNAL_ERROR");
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
    const snapshot = await deps.rpc("recipe_access_snapshot", {
      p_owner_id: auth.id,
      p_policy_version: deps.policyVersion,
      p_stage: deps.stage,
    });
    const valid = accessResponse(snapshot);
    requireThat(valid !== null, "SERVICE_UNAVAILABLE");
    return json(valid);
  } catch (err) {
    if (err instanceof Failure) return error(err.code, requestID);
    console.error("recipe_access_unhandled");
    return error("SERVICE_UNAVAILABLE", requestID);
  }
}
