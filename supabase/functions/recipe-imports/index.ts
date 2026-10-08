// Developer: gengyun
// Purpose: Exposes authenticated, idempotent RecipePouch import-job creation and lookup.

import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type ErrorCode =
  | "INVALID_INPUT"
  | "AUTH_REQUIRED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "ARTIFACT_NOT_READY"
  | "RATE_LIMITED"
  | "SERVICE_UNAVAILABLE"
  | "INTERNAL_ERROR";

interface ImportJob {
  id: string;
  client_request_id: string;
  status: string;
  stage: string;
  attempt_count: number;
  created_at: string;
  updated_at: string;
  server_received_at: string;
  queue_confirmed_at: string | null;
  recipe_id: string | null;
  recipe_status: string | null;
  review_count: number;
  error: Record<string, unknown> | null;
  result: Record<string, unknown> | null;
}

const MAX_BODY_BYTES = 500_000;

/// Consume at most maxBytes from the request stream. Content-Length is not
/// trusted: chunked requests and dishonest clients are enforced incrementally.
/// An invalid UTF-8 payload is rejected instead of silently substituted.
async function readBoundedJSONBody(
  request: Request,
  maxBytes: number,
): Promise<string | null> {
  const declaredLength = request.headers.get("content-length");
  if (declaredLength && Number(declaredLength) > maxBytes) return null;
  if (!request.body) return "";

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      total += next.value.byteLength;
      if (total > maxBytes) {
        await reader.cancel("Import request body exceeds size limit");
        return null;
      }
      chunks.push(next.value);
    }

    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(
  data: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return Response.json(data, { status, headers });
}

function allowedHeaders(request: Request): Headers {
  const headers = new Headers({
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    Vary: "Origin",
  });
  const origin = request.headers.get("Origin");
  const approved = (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "").split(",").map(
    (value) => value.trim(),
  );
  if (origin && approved.includes(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
  }
  return headers;
}

function failure(
  code: ErrorCode,
  message: string,
  httpStatus: number,
  recoverable = false,
  requestID: string = crypto.randomUUID(),
  suggestedAction: string | null = null,
  headers: HeadersInit = {},
): Response {
  return json(
    {
      code,
      message,
      recoverable,
      suggested_action: suggestedAction,
      request_id: requestID,
    },
    httpStatus,
    headers,
  );
}

function isPublicCandidateURL(raw: string): boolean {
  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    if (url.protocol !== "https:" || url.username || url.password) return false;
    if (url.port && url.port !== "443") return false;
    if (
      !host.includes(".") || host.endsWith(".local") ||
      host.endsWith(".internal") || host === "localhost"
    ) return false;
    if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) return false;
    if (host.startsWith("[") || host.includes(":")) return false;
    return raw.length <= 8192;
  } catch {
    return false;
  }
}

function toResponse(job: ImportJob): Record<string, unknown> {
  const value: Record<string, unknown> = {
    job_id: job.id,
    client_request_id: job.client_request_id,
    status: job.status,
    stage: job.stage,
    attempt_count: job.attempt_count,
    created_at: job.created_at,
    updated_at: job.updated_at,
    server_received_at: job.server_received_at,
  };
  if (job.queue_confirmed_at) value.queue_confirmed_at = job.queue_confirmed_at;
  if (job.recipe_id) value.recipe_id = job.recipe_id;
  if (job.recipe_status) value.recipe_status = job.recipe_status;
  if (job.review_count) value.review_count = job.review_count;
  if (job.error) value.error = job.error;
  if (job.result) value.result = job.result;
  return value;
}

function sqlFailure(
  error: { code?: string; message?: string },
  headers: Headers,
  requestID: string,
): Response {
  const message = error.message ?? "";
  if (
    message.includes("CLIENT_REQUEST_ID_CONFLICT") ||
    message.includes("NOT_RETRYABLE")
  ) {
    return failure(
      "CONFLICT",
      "This import request cannot be reused or retried.",
      409,
      false,
      requestID,
      null,
      headers,
    );
  }
  if (error.code === "22023" || message.includes("INVALID_INPUT")) {
    return failure(
      "INVALID_INPUT",
      "Provide one valid source and request ID.",
      400,
      false,
      requestID,
      null,
      headers,
    );
  }
  if (error.code === "42501") {
    return failure(
      "AUTH_REQUIRED",
      "Sign in to import a recipe.",
      401,
      true,
      requestID,
      "Sign in and retry.",
      headers,
    );
  }
  if (message.includes("RATE_LIMITED")) {
    return failure(
      "RATE_LIMITED",
      "Too many imports; retry later.",
      429,
      true,
      requestID,
      "Retry later.",
      headers,
    );
  }
  if (message.includes("NOT_FOUND")) {
    return failure(
      "NOT_FOUND",
      "This import was not found.",
      404,
      false,
      requestID,
      null,
      headers,
    );
  }
  if (message.includes("QUEUE_UNAVAILABLE")) {
    return failure(
      "SERVICE_UNAVAILABLE",
      "Recipe processing is temporarily unavailable.",
      503,
      true,
      requestID,
      "Keep your original source and retry.",
      headers,
    );
  }
  console.error("recipe_import_rpc_failed", { code: error.code });
  return failure(
    "INTERNAL_ERROR",
    "The import service encountered an error.",
    500,
    true,
    requestID,
    "Retry later.",
    headers,
  );
}

Deno.serve(async (request: Request): Promise<Response> => {
  const requestID = crypto.randomUUID();
  const headers = allowedHeaders(request);
  const origin = request.headers.get("Origin");
  if (origin && !headers.has("Access-Control-Allow-Origin")) {
    return failure(
      "FORBIDDEN",
      "This origin is not allowed.",
      403,
      false,
      requestID,
      null,
      headers,
    );
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }

  const token = request.headers.get("Authorization")?.match(/^Bearer (.+)$/i)
    ?.[1];
  if (!token) {
    return failure(
      "AUTH_REQUIRED",
      "Sign in to import a recipe.",
      401,
      true,
      requestID,
      null,
      headers,
    );
  }

  const serviceURL = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!serviceURL || !publicKey) {
    return failure(
      "SERVICE_UNAVAILABLE",
      "Import service configuration is incomplete.",
      503,
      true,
      requestID,
      null,
      headers,
    );
  }

  const client = createClient(serviceURL, publicKey, {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: authError } = await client.auth.getUser(token);
  if (authError || !userData.user || userData.user.is_anonymous) {
    return failure(
      "AUTH_REQUIRED",
      "Sign in with your RecipePouch account.",
      401,
      true,
      requestID,
      null,
      headers,
    );
  }

  const pathname = new URL(request.url).pathname.split("/").filter(Boolean);
  const baseIndex = pathname.lastIndexOf("recipe-imports");
  const tail = baseIndex >= 0 ? pathname.slice(baseIndex + 1) : [];
  const jobID = tail[0];

  if (request.method === "POST" && tail.length === 0) {
    const payload = await readBoundedJSONBody(request, MAX_BODY_BYTES);
    if (payload === null) {
      return failure(
        "INVALID_INPUT",
        "Import input is invalid or exceeds size limits.",
        413,
        false,
        requestID,
        null,
        headers,
      );
    }

    let params: Record<string, unknown>;
    try {
      params = JSON.parse(payload);
    } catch {
      return failure(
        "INVALID_INPUT",
        "Invalid JSON input.",
        400,
        false,
        requestID,
        null,
        headers,
      );
    }
    if (!params || typeof params !== "object" || Array.isArray(params)) {
      return failure(
        "INVALID_INPUT",
        "Expected a recipe source object.",
        400,
        false,
        requestID,
        null,
        headers,
      );
    }

    const id = params.client_request_id;
    const type = params.input_type;
    if (typeof id !== "string" || !UUID.test(id)) {
      return failure(
        "INVALID_INPUT",
        "A valid client_request_id is required.",
        400,
        false,
        requestID,
        null,
        headers,
      );
    }
    if (type === "image" || type === "file") {
      return failure(
        "ARTIFACT_NOT_READY",
        "Private media upload is not enabled yet.",
        422,
        true,
        requestID,
        "Add text or a link.",
        headers,
      );
    }

    const value = type === "url" ? params.url : params.text;
    if (
      typeof value !== "string" ||
      (type === "url" && !isPublicCandidateURL(value)) ||
      (type === "text" &&
        (value.trim().length === 0 || value.length > 100_000)) ||
      (type !== "url" && type !== "text")
    ) {
      return failure(
        "INVALID_INPUT",
        "Share a public HTTPS link or recipe text.",
        400,
        false,
        requestID,
        null,
        headers,
      );
    }
    const platform = params.platform_hint;
    if (
      platform != null && (typeof platform !== "string" || platform.length > 80)
    ) {
      return failure(
        "INVALID_INPUT",
        "Invalid source platform hint.",
        400,
        false,
        requestID,
        null,
        headers,
      );
    }

    const { data, error } = await client.rpc("submit_own_recipe_import", {
      p_client_request_id: id,
      p_input_type: type,
      p_source_value: value,
      p_platform_hint: platform ?? null,
    });
    if (error) return sqlFailure(error, headers, requestID);
    const row = (Array.isArray(data) ? data[0] : data) as ImportJob | undefined;
    if (!row) {
      return failure(
        "SERVICE_UNAVAILABLE",
        "No durable job was created.",
        503,
        true,
        requestID,
        null,
        headers,
      );
    }
    return json(toResponse(row), 202, headers);
  }

  if (
    jobID && UUID.test(jobID) && request.method === "GET" && tail.length === 1
  ) {
    const { data, error } = await client.from("recipe_import_jobs")
      .select("*")
      .eq("id", jobID)
      .eq("owner_id", userData.user.id)
      .maybeSingle();
    if (error) return sqlFailure(error, headers, requestID);
    if (!data) {
      return failure(
        "NOT_FOUND",
        "This import was not found.",
        404,
        false,
        requestID,
        null,
        headers,
      );
    }
    return json(toResponse(data as ImportJob), 200, headers);
  }

  if (
    jobID && UUID.test(jobID) && request.method === "POST" &&
    tail.length === 2 && tail[1] === "retry"
  ) {
    const { data, error } = await client.rpc("retry_own_recipe_import", {
      p_job_id: jobID,
    });
    if (error) return sqlFailure(error, headers, requestID);
    const row = (Array.isArray(data) ? data[0] : data) as ImportJob | undefined;
    if (!row) {
      return failure(
        "NOT_FOUND",
        "This import was not found.",
        404,
        false,
        requestID,
        null,
        headers,
      );
    }
    return json(toResponse(row), 202, headers);
  }

  return failure(
    "NOT_FOUND",
    "Unknown import endpoint.",
    404,
    false,
    requestID,
    null,
    headers,
  );
});
