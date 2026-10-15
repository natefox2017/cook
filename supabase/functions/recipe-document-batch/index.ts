// Developer: gengyun
// Purpose: Authenticated, owner-scoped bounded document batch scan endpoint.

import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { configuredOCRProvider } from "../recipe-import-worker/approvedOCRProvider.ts";
import {
  DocumentBatchError,
  buildDocumentBatchCandidates,
  buildDocumentBatchPageUnits,
  validateDocumentBatch,
  type DocumentBatchArtifact,
  type DocumentBatchCandidate,
  type DocumentBatchSpec,
} from "../recipe-import-worker/documentBatch.ts";
import { createDocumentBatchExtractor } from "./extractor.ts";
import {
  completeUpload,
  createUploadIntent,
  type UploadIntentBody,
} from "./upload.ts";

const BUCKET = "recipe-import-artifacts";
const MAX_BATCH_ITEMS = 10;
const MAX_BATCH_FILE_BYTES = 20 * 1024 * 1024;
const MAX_REQUEST_BYTES = 64 * 1024;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface BatchItemRequest {
  id?: unknown;
  input_type?: unknown;
  mime_type?: unknown;
  size_bytes?: unknown;
  page_count?: unknown;
}

interface ArtifactRow {
  id: string;
  owner_id: string;
  input_type: "image" | "file";
  storage_bucket: string;
  storage_path: string;
  mime_type: string;
  size_bytes: number;
  state: string;
  expires_at: string;
}

// Never trust Content-Length; read the declared items incrementally and reject
// a request that exceeds the small metadata ceiling.
async function readBoundedJSONBody(request: Request): Promise<Record<string, unknown> | null> {
  const declared = request.headers.get("content-length");
  if (declared && Number(declared) > MAX_REQUEST_BYTES) return null;
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      total += next.value.byteLength;
      if (total > MAX_REQUEST_BYTES) {
        await reader.cancel();
        return null;
      }
      chunks.push(next.value);
    }
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const value: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    return value && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

// Verifies the item is owner-scoped, unexpired and byte-for-byte the declared
// upload before any OCR egress. The batch allows 20 MiB per file; the durable
// storage ceiling is raised by the storage/schema owner.
async function resolveArtifact(
  admin: SupabaseClient,
  ownerID: string,
  item: BatchItemRequest,
): Promise<DocumentBatchArtifact> {
  const id = item.id;
  const inputType = item.input_type;
  const mimeType = item.mime_type;
  const sizeBytes = item.size_bytes;
  const pageCount = item.page_count;

  if (
    typeof id !== "string" || !UUID.test(id) ||
    (inputType !== "image" && inputType !== "file") ||
    typeof mimeType !== "string" ||
    !Number.isSafeInteger(sizeBytes) || (sizeBytes as number) < 1 ||
    (sizeBytes as number) > MAX_BATCH_FILE_BYTES ||
    !Number.isSafeInteger(pageCount) || (pageCount as number) < 1
  ) {
    throw new AppError("validation_error", "A batch item is invalid.", 400);
  }

  const { data, error } = await admin
    .from("recipe_import_artifacts")
    .select("id,owner_id,input_type,storage_bucket,storage_path,mime_type,size_bytes,state,expires_at")
    .eq("id", id)
    .eq("owner_id", ownerID)
    .maybeSingle();
  if (error) {
    throw new AppError("server_misconfigured", "Artifact lookup is unavailable.", 503);
  }
  if (!data) {
    throw new AppError("not_found", "Artifact not found.", 404);
  }
  const row = data as ArtifactRow;
  if (
    row.state !== "available" ||
    Date.parse(row.expires_at) <= Date.now() ||
    row.storage_bucket !== BUCKET ||
    row.storage_path !== `${ownerID}/${id}` ||
    row.input_type !== inputType ||
    row.mime_type !== mimeType ||
    row.size_bytes !== sizeBytes
  ) {
    throw new AppError("validation_error", "The artifact is not available or does not match the batch item.", 422);
  }

  const { data: blob, error: downloadError } = await admin
    .storage
    .from(BUCKET)
    .download(row.storage_path);
  if (downloadError || !blob) {
    throw new AppError("server_misconfigured", "Artifact download failed.", 503);
  }
  const bytes = new Uint8Array(await blob.arrayBuffer());
  if (bytes.length !== row.size_bytes) {
    throw new AppError("validation_error", "The artifact bytes changed after upload.", 422);
  }

  return {
    artifactID: id,
    inputType,
    mimeType,
    sizeBytes,
    bytes,
  };
}

// Derives a deterministic batch request ID from the selected artifact set so a
// retried scan resumes the same completed job instead of minting a duplicate.
async function stableBatchRequestID(artifactIDs: string[]): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode([...artifactIDs].sort().join("\n")),
    ),
  );
  const hex = Array.from(
    digest.slice(0, 16),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// Persists a real completed owner-scoped import job whose result carries the
// batch candidates, so the smart_import settle verifies a candidate is a member
// of an owned job instead of trusting a client success flag or a fabricated ID.
async function persistBatchJob(
  admin: SupabaseClient,
  ownerID: string,
  spec: DocumentBatchSpec,
  candidates: DocumentBatchCandidate[],
): Promise<{ jobID: string }> {
  const inputType = spec.kind === "pdf" ? "file" : "image";
  const primaryArtifactID = spec.artifacts[0].artifactID;
  const clientRequestID = await stableBatchRequestID(
    spec.artifacts.map((artifact) => artifact.artifactID),
  );
  const recipeID = crypto.randomUUID();

  const result = {
    recipe_id: recipeID,
    status: "needs_review",
    source: {
      input_type: inputType,
      original_url: null,
      canonical_url: null,
      source_artifact_id: primaryArtifactID,
      platform: null,
      author_name: null,
      source_title: null,
      external_content_id: null,
    },
    fields: {},
    evidence: [],
    review_fields: [],
    candidate_recipes: candidates.map((candidate) => ({
      candidate_id: candidate.candidate_id,
      title: candidate.title,
      ingredients: candidate.ingredients,
      steps: candidate.steps,
      evidence_ids: [],
      review_fields: [],
    })),
  };

  const { data: existing, error: existingError } = await admin
    .from("recipe_import_jobs")
    .select("id")
    .eq("owner_id", ownerID)
    .eq("client_request_id", clientRequestID)
    .maybeSingle();
  if (existingError) {
    throw new AppError("server_misconfigured", "Import job is unavailable.", 503);
  }
  if (existing) {
    return { jobID: existing.id as string };
  }

  const { data: inserted, error: insertError } = await admin
    .from("recipe_import_jobs")
    .insert({
      owner_id: ownerID,
      client_request_id: clientRequestID,
      input_type: inputType,
      source_value: primaryArtifactID,
      source_fingerprint: clientRequestID,
      artifact_id: primaryArtifactID,
      status: "completed",
      stage: "done",
      recipe_id: recipeID,
      recipe_status: "needs_review",
      review_count: candidates.length,
      result,
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .select("id")
    .single();
  if (insertError || !inserted) {
    throw new AppError("server_misconfigured", "Import job could not be persisted.", 503);
  }
  return { jobID: inserted.id as string };
}

Deno.serve(async (request: Request): Promise<Response> => {
  const cors = handleCors(request, "auth");
  if (cors) return cors;
  const headers = authCorsHeaders(request);

  try {
    if (request.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required.", 405);
    }
    const { user } = await requireUser(request);
    if (user.is_anonymous) {
      throw new AppError("unauthorized", "A signed-in account is required.", 401);
    }

    const segments = new URL(request.url).pathname.split("/").filter(Boolean);
    const baseIndex = segments.lastIndexOf("recipe-document-batch");
    const tail = baseIndex >= 0 ? segments.slice(baseIndex + 1) : [];

    const admin = createServiceClient();

    // POST /upload — create an idempotent 20 MiB upload intent and signed URL.
    if (tail.length === 1 && tail[0] === "upload") {
      const body = await readBoundedJSONBody(request);
      if (!body) {
        throw new AppError("validation_error", "Upload request is invalid or too large.", 413);
      }
      const intent = await createUploadIntent(admin, user.id, body as UploadIntentBody);
      return json(
        {
          artifact: intent.artifact,
          upload_path: intent.uploadPath,
          upload_token: intent.uploadToken,
        },
        200,
        headers,
      );
    }

    // POST /upload/:artifactID/complete — confirm bytes and mark available.
    if (tail.length === 3 && tail[0] === "upload" && tail[2] === "complete") {
      const artifactID = tail[1];
      if (!UUID.test(artifactID)) {
        throw new AppError("not_found", "Artifact not found.", 404);
      }
      const completed = await completeUpload(admin, user.id, artifactID);
      return json({ artifact: { artifact_id: completed.artifactID } }, 200, headers);
    }

    // POST / — resolve, validate and scan the referenced owner-scoped batch.
    if (tail.length === 0) {
      const body = await readBoundedJSONBody(request);
      if (!body || !Array.isArray(body.items)) {
        throw new AppError("validation_error", "Batch items are required.", 400);
      }
      const items = body.items as BatchItemRequest[];
      if (items.length < 1 || items.length > MAX_BATCH_ITEMS) {
        throw new AppError("validation_error", "A batch must contain 1 to 10 items.", 400);
      }

      const artifacts: DocumentBatchArtifact[] = [];
      for (const item of items) {
        artifacts.push(await resolveArtifact(admin, user.id, item));
      }

      const spec = validateDocumentBatch(artifacts);
      const units = buildDocumentBatchPageUnits(spec);
      const provider = configuredOCRProvider();
      const extractor = createDocumentBatchExtractor(
        new Map(artifacts.map((artifact) => [artifact.artifactID, artifact])),
        provider,
      );
      const { candidates, hasMore, unprocessed } = await buildDocumentBatchCandidates(
        units,
        extractor,
      );
      const { jobID } = await persistBatchJob(admin, user.id, spec, candidates);

      return json(
        {
          job_id: jobID,
          kind: spec.kind,
          page_count: spec.pageCount,
          total_bytes: spec.totalBytes,
          candidates,
          has_more: hasMore,
          unprocessed,
        },
        200,
        headers,
      );
    }

    throw new AppError("not_found", "Route not found.", 404);
  } catch (error) {
    if (error instanceof DocumentBatchError) {
      return json(
        { error: { code: error.code, message: error.message, details: null } },
        400,
        headers,
      );
    }
    return errorResponse(error, headers);
  }
});
