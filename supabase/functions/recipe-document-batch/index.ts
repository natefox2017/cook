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
} from "../recipe-import-worker/documentBatch.ts";
import { createDocumentBatchExtractor } from "./extractor.ts";

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

    const body = await readBoundedJSONBody(request);
    if (!body || !Array.isArray(body.items)) {
      throw new AppError("validation_error", "Batch items are required.", 400);
    }
    const items = body.items as BatchItemRequest[];
    if (items.length < 1 || items.length > MAX_BATCH_ITEMS) {
      throw new AppError("validation_error", "A batch must contain 1 to 10 items.", 400);
    }

    const admin = createServiceClient();
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

    return json(
      {
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
