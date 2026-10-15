// Developer: gengyun
// Purpose: 20 MiB owner-scoped artifact upload intent and completion for the document batch scan.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { AppError } from "../_shared/errors.ts";

export const DOCUMENT_BATCH_UPLOAD_MAX_BYTES = 20 * 1024 * 1024;
const BUCKET = "recipe-import-artifacts";
const UPLOAD_INTENT_SECONDS = 2 * 60 * 60;
const AVAILABLE_SECONDS = 7 * 24 * 60 * 60;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const IMAGE_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/heic",
  "image/heif",
]);
const FILE_TYPES = new Set(["application/pdf", "text/plain"]);

export interface UploadIntentBody {
  client_request_id?: unknown;
  input_type?: unknown;
  mime_type?: unknown;
  size_bytes?: unknown;
}

interface ArtifactRow {
  id: string;
  owner_id: string;
  input_type: "image" | "file";
  kind: "original" | "screenshot";
  storage_bucket: string;
  storage_path: string;
  mime_type: string;
  size_bytes: number;
  state: "upload_pending" | "available" | "rejected" | "expired";
  expires_at: string;
}

function artifactPayload(row: ArtifactRow): Record<string, unknown> {
  return {
    artifact_id: row.id,
    state: row.state,
    kind: row.kind,
    mime_type: row.mime_type,
    size_bytes: row.size_bytes,
    expires_at: row.expires_at,
  };
}

// Matches the single-source artifact byte-signature check so a batch upload
// carries the same MIME truthfulness guarantee before any OCR egress.
export function hasExpectedContent(data: Uint8Array, mimeType: string): boolean {
  if (mimeType === "image/jpeg") {
    return data.length >= 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff;
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
    const brands = new Set([
      "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1",
    ]);
    const major = new TextDecoder().decode(data.slice(8, 12));
    if (brands.has(major)) return true;
    for (let offset = 16; offset + 4 <= data.length; offset += 4) {
      if (brands.has(new TextDecoder().decode(data.slice(offset, offset + 4)))) {
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

// Creates an idempotent upload intent: the same (owner, client_request_id)
// resumes the original row instead of minting a second upload.
export async function createUploadIntent(
  admin: SupabaseClient,
  ownerID: string,
  body: UploadIntentBody,
): Promise<{ artifact: Record<string, unknown>; uploadPath: string; uploadToken: string }> {
  const inputType = body.input_type;
  const mimeType = body.mime_type;
  const sizeBytes = body.size_bytes;
  const clientRequestID = body.client_request_id;

  const validImage = inputType === "image" &&
    typeof mimeType === "string" && IMAGE_TYPES.has(mimeType);
  const validFile = inputType === "file" &&
    typeof mimeType === "string" && FILE_TYPES.has(mimeType);
  if (
    (!validImage && !validFile) ||
    typeof sizeBytes !== "number" || !Number.isSafeInteger(sizeBytes) ||
    sizeBytes < 1 || sizeBytes > DOCUMENT_BATCH_UPLOAD_MAX_BYTES ||
    typeof clientRequestID !== "string" || !UUID.test(clientRequestID)
  ) {
    throw new AppError("validation_error", "Unsupported artifact type or size.", 400);
  }

  const { data: existing, error: existingError } = await admin
    .from("recipe_import_artifacts")
    .select("*")
    .eq("owner_id", ownerID)
    .eq("client_request_id", clientRequestID)
    .maybeSingle();
  if (existingError) {
    throw new AppError("server_misconfigured", "Artifact upload is unavailable.", 503);
  }
  if (existing) {
    const row = existing as ArtifactRow;
    if (
      row.input_type !== inputType || row.mime_type !== mimeType ||
      row.size_bytes !== sizeBytes || Date.parse(row.expires_at) <= Date.now()
    ) {
      throw new AppError("validation_error", "This upload request conflicts with its original source.", 409);
    }
    if (row.state === "available") {
      return {
        artifact: artifactPayload(row),
        uploadPath: row.storage_path,
        uploadToken: "",
      };
    }
    if (row.state !== "upload_pending") {
      throw new AppError("validation_error", "The artifact is not available for upload.", 422);
    }
    const { data: signedUpload, error: signedError } = await admin.storage
      .from(BUCKET)
      .createSignedUploadUrl(row.storage_path, { upsert: false });
    if (signedError || !signedUpload) {
      throw new AppError("server_misconfigured", "Artifact upload is unavailable.", 503);
    }
    return {
      artifact: artifactPayload(row),
      uploadPath: row.storage_path,
      uploadToken: signedUpload.token,
    };
  }

  const id = crypto.randomUUID();
  const path = `${ownerID}/${id}`;
  const row: ArtifactRow = {
    id,
    owner_id: ownerID,
    input_type: inputType as "image" | "file",
    kind: validImage ? "screenshot" : "original",
    storage_bucket: BUCKET,
    storage_path: path,
    mime_type: mimeType as string,
    size_bytes: sizeBytes as number,
    state: "upload_pending",
    expires_at: new Date(Date.now() + UPLOAD_INTENT_SECONDS * 1_000).toISOString(),
  };
  const { data: inserted, error: insertError } = await admin
    .from("recipe_import_artifacts")
    .insert(row)
    .select("*")
    .single();
  if (insertError || !inserted) {
    throw new AppError("server_misconfigured", "Artifact upload is unavailable.", 503);
  }

  const { data: signedUpload, error: signedError } = await admin.storage
    .from(BUCKET)
    .createSignedUploadUrl(path, { upsert: false });
  if (signedError || !signedUpload) {
    await admin.from("recipe_import_artifacts").delete().eq("id", id);
    throw new AppError("server_misconfigured", "Artifact upload is unavailable.", 503);
  }
  return {
    artifact: artifactPayload(inserted as ArtifactRow),
    uploadPath: path,
    uploadToken: signedUpload.token,
  };
}

// Confirms an owner-scoped upload byte-for-byte against its declared size and
// MIME signature, then makes it available to the batch processor.
export async function completeUpload(
  admin: SupabaseClient,
  ownerID: string,
  artifactID: string,
): Promise<{ artifactID: string }> {
  const { data: artifact, error: lookupError } = await admin
    .from("recipe_import_artifacts")
    .select("*")
    .eq("id", artifactID)
    .eq("owner_id", ownerID)
    .maybeSingle();
  if (lookupError) {
    throw new AppError("server_misconfigured", "Artifact is unavailable.", 503);
  }
  if (!artifact) {
    throw new AppError("not_found", "Artifact not found.", 404);
  }
  const row = artifact as ArtifactRow;

  if (row.state === "available" && Date.parse(row.expires_at) > Date.now()) {
    return { artifactID: row.id };
  }
  if (row.state !== "upload_pending" || Date.parse(row.expires_at) <= Date.now()) {
    throw new AppError("validation_error", "The upload intent has expired.", 422);
  }

  const { data: entries, error: listError } = await admin.storage
    .from(BUCKET)
    .list(ownerID, { limit: 100, search: artifactID });
  const object = entries?.find((entry) => entry.name === artifactID);
  const metadata = object?.metadata as Record<string, unknown> | undefined;
  const actualSize = Number(metadata?.size);
  const actualType = String(metadata?.mimetype ?? "").toLowerCase();
  if (
    listError || !object || actualSize !== row.size_bytes || actualType !== row.mime_type
  ) {
    throw new AppError("validation_error", "The uploaded file could not be confirmed.", 422);
  }

  const { data: storedFile, error: downloadError } = await admin.storage
    .from(BUCKET)
    .download(row.storage_path);
  if (downloadError || !storedFile || storedFile.size !== row.size_bytes) {
    throw new AppError("validation_error", "The uploaded file could not be confirmed.", 422);
  }
  const bytes = new Uint8Array(await storedFile.arrayBuffer());
  if (!hasExpectedContent(bytes, row.mime_type)) {
    await admin.storage.from(BUCKET).remove([row.storage_path]);
    await admin.from("recipe_import_artifacts").update({
      state: "rejected",
      expires_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", row.id).eq("owner_id", ownerID);
    throw new AppError("validation_error", "The uploaded bytes do not match the declared file type.", 422);
  }

  const { data: updated, error: updateError } = await admin
    .from("recipe_import_artifacts")
    .update({
      state: "available",
      uploaded_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + AVAILABLE_SECONDS * 1_000).toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", row.id)
    .eq("owner_id", ownerID)
    .eq("state", "upload_pending")
    .gt("expires_at", new Date().toISOString())
    .select("*")
    .maybeSingle();
  if (updateError || !updated) {
    const { data: confirmed } = await admin
      .from("recipe_import_artifacts")
      .select("*")
      .eq("id", row.id)
      .eq("owner_id", ownerID)
      .maybeSingle();
    if (confirmed?.state === "available" && Date.parse(confirmed.expires_at) > Date.now()) {
      return { artifactID: row.id };
    }
    throw new AppError("server_misconfigured", "Artifact could not be confirmed.", 503);
  }
  return { artifactID: row.id };
}
