// Developer: gengyun
// Purpose: Manages authenticated, private recipe import artifact uploads and reads.

import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";

const BUCKET = "recipe-import-artifacts";
const MAX_BYTES = 10 * 1024 * 1024;
const UPLOAD_INTENT_SECONDS = 2 * 60 * 60;
const DOWNLOAD_URL_SECONDS = 60;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const IMAGE_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/heic",
  "image/heif",
]);
const FILE_TYPES = new Set(["application/pdf", "text/plain"]);

interface ArtifactRow {
  id: string;
  owner_id: string;
  input_type: "image" | "file";
  kind: "original" | "screenshot";
  storage_bucket: string;
  storage_path: string;
  mime_type: string;
  size_bytes: number;
  checksum_sha256: string | null;
  state: "upload_pending" | "available" | "rejected" | "expired";
  expires_at: string;
  uploaded_at: string | null;
}

function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return Response.json(data, { status, headers });
}

function errorResponse(
  code: string,
  message: string,
  status: number,
  headers: HeadersInit,
): Response {
  return json({
    code,
    message,
    recoverable: status >= 500,
    request_id: crypto.randomUUID(),
  }, status, headers);
}

function artifactResponse(artifact: ArtifactRow): Record<string, unknown> {
  return {
    artifact_id: artifact.id,
    state: artifact.state,
    kind: artifact.kind,
    mime_type: artifact.mime_type,
    size_bytes: artifact.size_bytes,
    checksum_sha256: artifact.checksum_sha256,
    expires_at: artifact.expires_at,
  };
}

function hasExpectedContent(data: Uint8Array, mimeType: string): boolean {
  if (mimeType === "image/jpeg") {
    return data.length >= 3 && data[0] === 0xff && data[1] === 0xd8 &&
      data[2] === 0xff;
  }
  if (mimeType === "image/png") {
    return data.length >= 8 &&
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every(
        (byte, index) => data[index] === byte,
      );
  }
  if (mimeType === "image/heic" || mimeType === "image/heif") {
    if (data.length < 16 || new TextDecoder().decode(data.slice(4, 8)) !== "ftyp") {
      return false;
    }
    const supportedBrands = new Set([
      "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1",
    ]);
    const majorBrand = new TextDecoder().decode(data.slice(8, 12));
    if (supportedBrands.has(majorBrand)) return true;
    for (let offset = 16; offset + 4 <= data.length; offset += 4) {
      if (supportedBrands.has(new TextDecoder().decode(data.slice(offset, offset + 4)))) {
        return true;
      }
    }
    return false;
  }
  if (mimeType === "application/pdf") {
    return data.length >= 5 && new TextDecoder().decode(data.slice(0, 5)) === "%PDF-";
  }
  if (mimeType === "text/plain") {
    if (data.includes(0)) return false;
    try {
      new TextDecoder("utf-8", { fatal: true }).decode(data);
      return true;
    } catch {
      return false;
    }
  }
  return false;
}

async function readSmallJSON(request: Request): Promise<Record<string, unknown> | null> {
  const declaredLength = request.headers.get("content-length");
  if (declaredLength && Number(declaredLength) > 2_048) return null;
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      total += next.value.byteLength;
      if (total > 2_048) {
        await reader.cancel();
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
    const value: unknown = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    return value && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : null;
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
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
    const segments = new URL(request.url).pathname.split("/").filter(Boolean);
    const baseIndex = segments.lastIndexOf("recipe-import-artifacts");
    const tail = baseIndex >= 0 ? segments.slice(baseIndex + 1) : [];
    if (baseIndex < 0) {
      return errorResponse("NOT_FOUND", "Artifact route not found.", 404, headers);
    }

    if (request.method === "POST" && tail.length === 0) {
      const body = await readSmallJSON(request);
      if (!body) {
        return errorResponse("INVALID_INPUT", "Artifact request is invalid or too large.", 413, headers);
      }
      const inputType = body?.input_type;
      const mimeType = body?.mime_type;
      const size = body?.size_bytes;
      const clientRequestID = body?.client_request_id;
      const validImage = inputType === "image" &&
        typeof mimeType === "string" && IMAGE_TYPES.has(mimeType);
      const validFile = inputType === "file" &&
        typeof mimeType === "string" && FILE_TYPES.has(mimeType);
      if (
        (!validImage && !validFile) || typeof size !== "number" ||
        !Number.isSafeInteger(size) || size < 1 || size > MAX_BYTES ||
        typeof clientRequestID !== "string" || !UUID.test(clientRequestID)
      ) {
        return errorResponse("INVALID_INPUT", "Unsupported artifact type or size.", 400, headers);
      }

      const { data: existing, error: existingError } = await admin.from(
        "recipe_import_artifacts",
      ).select("*").eq("owner_id", user.id)
        .eq("client_request_id", clientRequestID).maybeSingle();
      if (existingError) {
        return errorResponse("SERVICE_UNAVAILABLE", "Artifact upload is unavailable.", 503, headers);
      }
      if (existing) {
        const row = existing as ArtifactRow;
        if (
          row.input_type !== inputType || row.mime_type !== mimeType ||
          row.size_bytes !== size || Date.parse(row.expires_at) <= Date.now()
        ) {
          return errorResponse("ARTIFACT_NOT_READY", "This artifact request expired or conflicts with its original source.", 409, headers);
        }
        if (row.state === "available") {
          return json({ artifact: artifactResponse(row) }, 200, headers);
        }
        if (row.state !== "upload_pending") {
          return errorResponse("ARTIFACT_NOT_READY", "The artifact is not available for upload.", 422, headers);
        }
        const { data: signedUpload, error: signedError } = await admin.storage
          .from(BUCKET)
          .createSignedUploadUrl(row.storage_path, { upsert: false });
        if (signedError || !signedUpload) {
          return errorResponse("SERVICE_UNAVAILABLE", "Artifact upload is unavailable.", 503, headers);
        }
        return json({
          artifact: artifactResponse(row),
          upload_path: row.storage_path,
          upload_token: signedUpload.token,
        }, 200, headers);
      }

      const id = crypto.randomUUID();
      const path = `${user.id}/${id}`;
      const expiresAt = new Date(Date.now() + UPLOAD_INTENT_SECONDS * 1_000)
        .toISOString();
      const row = {
        id,
        owner_id: user.id,
        client_request_id: clientRequestID,
        input_type: inputType,
        kind: validImage ? "screenshot" : "original",
        storage_bucket: BUCKET,
        storage_path: path,
        mime_type: mimeType,
        size_bytes: size,
        state: "upload_pending",
        expires_at: expiresAt,
      };
      const { data, error } = await admin.from("recipe_import_artifacts")
        .insert(row)
        .select("*")
        .single();
      if (error || !data) {
        return errorResponse("SERVICE_UNAVAILABLE", "Artifact upload is unavailable.", 503, headers);
      }

      const { data: signedUpload, error: signedError } = await admin.storage
        .from(BUCKET)
        .createSignedUploadUrl(path, { upsert: false });
      if (signedError || !signedUpload) {
        await admin.from("recipe_import_artifacts").delete().eq("id", id);
        return errorResponse("SERVICE_UNAVAILABLE", "Artifact upload is unavailable.", 503, headers);
      }
      return json({
        artifact: artifactResponse(data as ArtifactRow),
        upload_path: path,
        upload_token: signedUpload.token,
      }, 201, headers);
    }

    const artifactID = tail[0];
    if (!artifactID || !UUID.test(artifactID)) {
      return errorResponse("NOT_FOUND", "Artifact not found.", 404, headers);
    }
    const { data: artifact, error: lookupError } = await admin.from(
      "recipe_import_artifacts",
    ).select("*").eq("id", artifactID).eq("owner_id", user.id).maybeSingle();
    if (lookupError) {
      return errorResponse("SERVICE_UNAVAILABLE", "Artifact is unavailable.", 503, headers);
    }
    if (!artifact) {
      return errorResponse("NOT_FOUND", "Artifact not found.", 404, headers);
    }
    const row = artifact as ArtifactRow;

    if (request.method === "POST" && tail.length === 2 && tail[1] === "complete") {
      // Completion can be retried after a response was lost. Do not turn a
      // previously confirmed, still-valid upload into a permanent 422.
      if (row.state === "available" && Date.parse(row.expires_at) > Date.now()) {
        return json({ artifact: artifactResponse(row) }, 200, headers);
      }
      if (row.state !== "upload_pending" || Date.parse(row.expires_at) <= Date.now()) {
        return errorResponse("ARTIFACT_NOT_READY", "The upload intent has expired.", 422, headers);
      }
      const { data: entries, error: listError } = await admin.storage
        .from(BUCKET)
        .list(user.id, { limit: 100, search: artifactID });
      const object = entries?.find((entry) => entry.name === artifactID);
      const metadata = object?.metadata as Record<string, unknown> | undefined;
      const actualSize = Number(metadata?.size);
      const actualType = String(metadata?.mimetype ?? "").toLowerCase();
      if (
        listError || !object || actualSize !== row.size_bytes ||
        actualType !== row.mime_type
      ) {
        return errorResponse("ARTIFACT_NOT_READY", "The uploaded file could not be confirmed.", 422, headers);
      }
      const { data: storedFile, error: downloadError } = await admin.storage
        .from(BUCKET)
        .download(row.storage_path);
      if (downloadError || !storedFile || storedFile.size !== row.size_bytes) {
        return errorResponse("ARTIFACT_NOT_READY", "The uploaded file could not be confirmed.", 422, headers);
      }
      const bytes = new Uint8Array(await storedFile.arrayBuffer());
      if (!hasExpectedContent(bytes, row.mime_type)) {
        await admin.storage.from(BUCKET).remove([row.storage_path]);
        await admin.from("recipe_import_artifacts").update({
          state: "rejected",
          expires_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("id", row.id).eq("owner_id", user.id);
        return errorResponse("INVALID_INPUT", "The uploaded bytes do not match the declared file type.", 422, headers);
      }
      const availableUntil = new Date(Date.now() + 7 * 24 * 60 * 60 * 1_000)
        .toISOString();
      const { data: updated, error: updateError } = await admin.from(
        "recipe_import_artifacts",
      ).update({
        state: "available",
        uploaded_at: new Date().toISOString(),
        expires_at: availableUntil,
        updated_at: new Date().toISOString(),
      }).eq("id", row.id).eq("owner_id", user.id).eq("state", "upload_pending")
        .select("*").maybeSingle();
      if (updateError || !updated) {
        // Another completion request may have won the conditional update.
        // Re-read the same owner-scoped row rather than rejecting a confirmed
        // upload as a service failure.
        if (!updateError) {
          const { data: confirmed } = await admin.from("recipe_import_artifacts")
            .select("*").eq("id", row.id).eq("owner_id", user.id).maybeSingle();
          if (confirmed?.state === "available" &&
            Date.parse(confirmed.expires_at) > Date.now()) {
            return json({ artifact: artifactResponse(confirmed as ArtifactRow) }, 200, headers);
          }
        }
        return errorResponse("SERVICE_UNAVAILABLE", "Artifact could not be confirmed.", 503, headers);
      }
      return json({ artifact: artifactResponse(updated as ArtifactRow) }, 200, headers);
    }

    if (request.method === "GET" && tail.length === 2 && tail[1] === "download") {
      if (row.state !== "available" || Date.parse(row.expires_at) <= Date.now()) {
        return errorResponse("ARTIFACT_NOT_READY", "Artifact is no longer available.", 404, headers);
      }
      const { data: signed, error } = await admin.storage.from(BUCKET)
        .createSignedUrl(row.storage_path, DOWNLOAD_URL_SECONDS);
      if (error || !signed) {
        return errorResponse("SERVICE_UNAVAILABLE", "Artifact download is unavailable.", 503, headers);
      }
      return json({
        artifact: artifactResponse(row),
        download_url: signed.signedUrl,
        expires_in_seconds: DOWNLOAD_URL_SECONDS,
      }, 200, headers);
    }

    if (request.method === "DELETE" && tail.length === 1) {
      if (row.state !== "expired") {
        const { error } = await admin.storage.from(BUCKET).remove([row.storage_path]);
        if (error) {
          return errorResponse("SERVICE_UNAVAILABLE", "Artifact could not be deleted.", 503, headers);
        }
      }
      const { error } = await admin.from("recipe_import_artifacts").update({
        state: "expired",
        expires_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", row.id).eq("owner_id", user.id);
      if (error) {
        return errorResponse("SERVICE_UNAVAILABLE", "Artifact could not be deleted.", 503, headers);
      }
      return json({ artifact_id: row.id, state: "expired" }, 200, headers);
    }

    return errorResponse("NOT_FOUND", "Artifact route not found.", 404, headers);
  } catch (error) {
    const status = error instanceof Error && "status" in error
      ? Number(error.status)
      : 500;
    return errorResponse(
      status === 401 ? "AUTH_REQUIRED" : "INTERNAL_ERROR",
      status === 401 ? "A signed-in session is required." : "Artifact request failed.",
      status === 401 ? 401 : 500,
      headers,
    );
  }
});
