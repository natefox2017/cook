// Developer: gengyun
// Purpose: Validates private artifact ownership and extracts bounded UTF-8 source evidence.

import { parseLocalText } from "./textEvidence.ts";
import type { ParsedWebRecipe } from "./schemaRecipe.ts";

const BUCKET = "recipe-import-artifacts";
const MAX_BYTES = 10 * 1024 * 1024;
const MAX_CHARACTERS = 100_000;

export interface PrivateArtifactRow {
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

export function isOwnerScopedAvailableArtifact(
  row: PrivateArtifactRow | null,
  request: { ownerID: string; artifactID: string | null; inputType: "image" | "file" },
  at: number = Date.now(),
): row is PrivateArtifactRow {
  if (!row || !request.artifactID) return false;
  const expiry = Date.parse(row.expires_at);
  return row.id === request.artifactID &&
    row.owner_id === request.ownerID &&
    row.input_type === request.inputType &&
    row.storage_bucket === BUCKET &&
    row.storage_path === `${request.ownerID}/${request.artifactID}` &&
    row.state === "available" &&
    Number.isFinite(expiry) && expiry > at &&
    Number.isSafeInteger(row.size_bytes) &&
    row.size_bytes >= 1 && row.size_bytes <= MAX_BYTES;
}

export class ArtifactTextError extends Error {
  constructor(
    readonly code: "ARTIFACT_INVALID_TEXT" | "ARTIFACT_TOO_LARGE",
    message: string,
  ) {
    super(message);
    this.name = "ArtifactTextError";
  }
}

export async function decodePlainTextArtifact(
  blob: Blob,
  expectedBytes: number,
): Promise<string> {
  if (
    !Number.isSafeInteger(expectedBytes) || expectedBytes < 1 ||
    expectedBytes > MAX_BYTES || blob.size !== expectedBytes
  ) {
    throw new ArtifactTextError(
      "ARTIFACT_TOO_LARGE",
      "The shared text file does not match its recorded size.",
    );
  }

  // Signed-upload completion already checks the file type. Revalidate the
  // bytes in the worker: an unreadable or truncated file cannot be evidence.
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(
      await blob.arrayBuffer(),
    );
  } catch {
    throw new ArtifactTextError(
      "ARTIFACT_INVALID_TEXT",
      "The shared file is not valid UTF-8 text.",
    );
  }
  if (text.includes("\0") || !text.trim()) {
    throw new ArtifactTextError(
      "ARTIFACT_INVALID_TEXT",
      "The shared file has no readable recipe text.",
    );
  }
  if (text.length > MAX_CHARACTERS) {
    throw new ArtifactTextError(
      "ARTIFACT_TOO_LARGE",
      "The shared text is too long to extract safely.",
    );
  }
  return text;
}

export function parsePlainTextArtifact(input: {
  id: string;
  text: string;
  artifactID: string;
  platformHint: string | null;
  originalSourceURL?: string | null;
}): ParsedWebRecipe {
  const extracted = parseLocalText({
    id: input.id,
    source_value: input.text,
    original_source_url: input.originalSourceURL,
    platform_hint: input.platformHint,
  });

  // Preserve the actual file input_type and immutable source_artifact_id.
  // Evidence IDs must remain the ones referenced by extracted field paths.
  return {
    recipe_id: input.id,
    status: extracted.status,
    source: {
      input_type: "file",
      original_url: input.originalSourceURL ?? null,
      canonical_url: null,
      source_artifact_id: input.artifactID,
      platform: input.platformHint,
      author_name: null,
      source_title: null,
    },
    fields: extracted.fields,
    evidence: extracted.evidence.map((item) => ({
      ...item,
      source_artifact_id: input.artifactID,
    })),
    review_fields: extracted.review_fields,
  };
}
