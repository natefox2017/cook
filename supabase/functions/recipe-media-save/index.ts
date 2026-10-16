// Developer: gengyun
// Purpose: DEV-78 user-selected save callsite for media imports. Atomically
//          reserves media_import plus one smart_import unit per selected
//          candidate before any finalize, then settles/releases the media unit.
//          Candidate smart_import finalize/release stays the existing recipe-usage
//          flow (DEV-430). Media metering is closed by default (freeTest).

import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError } from "../_shared/errors.ts";
import { extractImportPayload, resolveStage } from "../_shared/recipeAccess.ts";
import {
  createLedgerRPC,
  releaseMediaImport,
  reserveMediaBundle,
  settleMediaImport,
} from "../recipe-import-worker/mediaUsage.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_CANDIDATES = 8;

function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return Response.json(data, { status, headers });
}

function errorResponse(
  code: string,
  message: string,
  status: number,
  headers: HeadersInit,
): Response {
  return json({ code, message }, status, headers);
}

function candidateValidationError(candidateIDs: unknown): string | null {
  if (
    !Array.isArray(candidateIDs) || candidateIDs.length < 1 ||
    candidateIDs.length > MAX_CANDIDATES
  ) {
    return "candidate_ids must be a non-empty array of at most 8 ids.";
  }
  const seen = new Set<string>();
  for (const id of candidateIDs) {
    if (typeof id !== "string" || id.length < 1 || id.length > 256) {
      return "candidate_ids must be non-empty strings.";
    }
    if (seen.has(id)) return "candidate_ids must not contain duplicates.";
    seen.add(id);
  }
  return null;
}

Deno.serve(async (request: Request): Promise<Response> => {
  const cors = handleCors(request, "auth");
  if (cors) return cors;
  const headers = authCorsHeaders(request);

  try {
    const { user } = await requireUser(request);
    if (user.is_anonymous) {
      return errorResponse("AUTH_REQUIRED", "A signed-in account is required.", 401, headers);
    }
    const admin = createServiceClient();
    const rpc = createLedgerRPC((name, args) => admin.rpc(name, args));

    const segments = new URL(request.url).pathname.split("/").filter(Boolean);
    const baseIndex = segments.lastIndexOf("recipe-media-save");
    const action = baseIndex >= 0 ? segments[baseIndex + 1] : undefined;

    if (request.method !== "POST") {
      return errorResponse("METHOD_NOT_ALLOWED", "POST required.", 405, headers);
    }

    const body = await request.json().catch(() => null);
    const jobID = body?.job_id;
    if (typeof jobID !== "string" || !UUID.test(jobID)) {
      return errorResponse("INVALID_INPUT", "job_id must be a UUID.", 400, headers);
    }

    // Media metering is closed by default: outside the commercial stage the
    // premium bundle fails closed and never fakes a free success or activates
    // the stage.
    if (resolveStage(Deno.env.get("RECIPE_COMMERCIAL_STAGE")) !== "commercial") {
      return errorResponse(
        "SERVICE_UNAVAILABLE",
        "Commercial media metering is unavailable in the current release stage.",
        503,
        headers,
      );
    }

    const { data: job, error: jobError } = await admin.from("recipe_import_jobs")
      .select("id,owner_id,status,result")
      .eq("id", jobID)
      .eq("owner_id", user.id)
      .maybeSingle();
    if (jobError) {
      return errorResponse("SERVICE_UNAVAILABLE", "The import job is unavailable.", 503, headers);
    }
    if (!job) {
      return errorResponse("NOT_FOUND", "The import job was not found.", 404, headers);
    }
    if (job.status !== "completed") {
      return errorResponse("JOB_NOT_READY", "The import job is not completed.", 409, headers);
    }

    if (action === "reserve") {
      const candidateIDs = body?.candidate_ids;
      const invalid = candidateValidationError(candidateIDs);
      if (invalid) return errorResponse("INVALID_INPUT", invalid, 400, headers);
      // Verify each selected candidate is an actual member of the owned job
      // result before reserving; never trust the client selection alone.
      for (const id of candidateIDs) {
        if (extractImportPayload(job.result, id) === null) {
          return errorResponse(
            "CANDIDATE_NOT_IN_JOB",
            `Candidate ${id} is not a member of the job result.`,
            422,
            headers,
          );
        }
      }
      const result = await reserveMediaBundle(
        rpc,
        user.id,
        jobID,
        candidateIDs,
      );
      if (result.code === "RESERVED" || result.code === "REPLAY") {
        return json({
          code: result.code,
          operation_id: result.operationId,
          media: result.media,
          candidates: result.candidates,
        }, 200, headers);
      }
      const message = "message" in result
        ? result.message
        : "The media bundle reservation was rejected.";
      const status = result.code === "UPGRADE_REQUIRED"
        ? 402
        : result.code === "QUOTA_EXCEEDED"
        ? 409
        : 422;
      return errorResponse(result.code, message, status, headers);
    }

    if (action === "finalize") {
      // Settle the media_import unit. Per-candidate smart_import finalize is
      // the existing recipe-usage flow (DEV-430), not this endpoint.
      const rawPayload = body?.payload;
      const payload = rawPayload !== null && typeof rawPayload === "object" &&
        !Array.isArray(rawPayload)
        ? rawPayload
        : { media_task_id: jobID };
      const result = await settleMediaImport(rpc, user.id, jobID, payload);
      return json({ code: result.code ?? "FINALIZED", operation_id: jobID }, 200, headers);
    }

    if (action === "release") {
      await releaseMediaImport(rpc, user.id, jobID);
      return json({ code: "RELEASED", operation_id: jobID }, 200, headers);
    }

    return errorResponse("NOT_FOUND", "Unknown media save route.", 404, headers);
  } catch (error) {
    const status = error instanceof AppError ? error.status : 500;
    return errorResponse(
      status === 401 ? "AUTH_REQUIRED" : "INTERNAL_ERROR",
      status === 401
        ? "A signed-in session is required."
        : "The media save request failed.",
      status === 401 ? 401 : 500,
      headers,
    );
  }
});
