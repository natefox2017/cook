// Developer: RecipePouch
// Purpose: Parse private UTF-8 text artifacts without inventing cooking evidence.

import type { ParsedWebRecipe } from "./schemaRecipe.ts";
import { parseLocalText } from "./textEvidence.ts";

export const MAX_TEXT_ARTIFACT_BYTES = 100_000;

export class TextArtifactError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TextArtifactError";
  }
}

/** A malformed or oversized attachment must remain available for manual review. */
export function decodeTextArtifact(bytes: Uint8Array): string {
  if (bytes.byteLength < 1 || bytes.byteLength > MAX_TEXT_ARTIFACT_BYTES) {
    throw new TextArtifactError("Text attachment exceeds the supported size.");
  }

  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new TextArtifactError("Text attachment is not valid UTF-8.");
  }

  if (!text.trim() || text.includes("\u0000")) {
    throw new TextArtifactError("Text attachment is empty or not plain text.");
  }
  return text;
}

export function parseTextArtifact(input: {
  jobID: string;
  artifactID: string;
  originalSourceURL: string | null;
  platformHint: string | null;
  bytes: Uint8Array;
}): ParsedWebRecipe {
  const parsed = parseLocalText({
    id: input.jobID,
    source_value: decodeTextArtifact(input.bytes),
    original_source_url: input.originalSourceURL,
    platform_hint: input.platformHint,
  });

  return {
    recipe_id: parsed.recipe_id,
    status: parsed.status,
    source: {
      input_type: "file",
      original_url: parsed.source.original_url,
      canonical_url: null,
      source_artifact_id: input.artifactID,
      platform: parsed.source.platform,
      author_name: null,
      source_title: null,
    },
    fields: parsed.fields,
    evidence: parsed.evidence.map((item) => ({
      ...item,
      source_artifact_id: input.artifactID,
    })),
    review_fields: parsed.review_fields,
  };
}
