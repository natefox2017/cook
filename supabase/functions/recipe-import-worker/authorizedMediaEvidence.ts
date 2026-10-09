// Purpose: Strictly validate legally obtained audiovisual evidence before recipe inference.
// This module NEVER fetches or downloads media, reads credentials, or bypasses platform controls.

import type { ParsedWebRecipe } from "./schemaRecipe.ts";

export type AuthorizedMediaMethod = "owner_uploaded" | "approved_public_api";
export type MediaEvidenceKind = "subtitle" | "audio_transcript" | "keyframe_text";

export interface MediaEvidenceSegment {
  kind: MediaEvidenceKind;
  excerpt: string;
  startSeconds: number;
  endSeconds: number;
  confidence?: number | null;
}

export interface AuthorizedMediaEvidence {
  // Server-side verification reference. Never trust this value from a public client.
  authorizationMethod: AuthorizedMediaMethod;
  authorizationReference: string;
  sourceDurationSeconds: number;
  segments: MediaEvidenceSegment[];
}

const MAX_DURATION_SECONDS = 3_600;
const MAX_SEGMENTS = 60;
const MAX_EXCERPT_LENGTH = 1_500;
const MAX_TOTAL_EXCERPT_LENGTH = 20_000;

function validSeconds(start: number, end: number, max: number): boolean {
  return Number.isFinite(start) && Number.isFinite(end) && start >= 0 &&
    end >= start && end <= max;
}

/**
 * Appends source-text evidence only. The caller must still validate media access,
 * user ownership, provider capabilities and expiration before invoking this.
 * No recipe fields/ingredients/temperatures are fabricated from raw media.
 */
export function attachAuthorizedMediaEvidence(
  result: ParsedWebRecipe,
  source: AuthorizedMediaEvidence,
): ParsedWebRecipe {
  if (
    !["owner_uploaded", "approved_public_api"].includes(
      source.authorizationMethod,
    ) ||
    typeof source.authorizationReference !== "string" ||
    !/^[a-zA-Z0-9:_-]{8,512}$/.test(source.authorizationReference) ||
    !Number.isFinite(source.sourceDurationSeconds) ||
    source.sourceDurationSeconds <= 0 ||
    source.sourceDurationSeconds > MAX_DURATION_SECONDS ||
    !Array.isArray(source.segments) ||
    source.segments.length === 0 ||
    source.segments.length > MAX_SEGMENTS
  ) {
    throw new Error("Unauthorized or oversized media evidence");
  }
  let total = 0;
  const evidence: Array<Record<string, unknown>> = [];
  const dedupe = new Set<string>();
  const capturedAt = new Date().toISOString();
  for (const segment of source.segments) {
    if (
      !["subtitle", "audio_transcript", "keyframe_text"].includes(segment.kind) ||
      typeof segment.excerpt !== "string" ||
      !segment.excerpt.trim() ||
      segment.excerpt.length > MAX_EXCERPT_LENGTH ||
      !validSeconds(
        segment.startSeconds, segment.endSeconds,
        source.sourceDurationSeconds,
      ) ||
      (segment.confidence != null &&
        (!Number.isFinite(segment.confidence) ||
          segment.confidence < 0 || segment.confidence > 1))
    ) {
      throw new Error("Invalid timestamped media evidence");
    }
    total += segment.excerpt.length;
    if (total > MAX_TOTAL_EXCERPT_LENGTH) {
      throw new Error("Total media evidence budget exceeded");
    }
    const key = [
      segment.kind, segment.startSeconds, segment.endSeconds, segment.excerpt,
    ].join("\u0000");
    if (dedupe.has(key)) continue;
    dedupe.add(key);
    evidence.push({
      id: crypto.randomUUID(),
      source_type: segment.kind,
      origin: source.authorizationMethod,
      excerpt: segment.excerpt,
      confidence: segment.confidence ?? null,
      timestamp_start_seconds: segment.startSeconds,
      timestamp_end_seconds: segment.endSeconds,
      captured_at: capturedAt,
    });
  }
  return {
    ...result,
    evidence: [...result.evidence, ...evidence],
    review_fields: result.status === "needs_review"
      ? [...new Set([...result.review_fields, "media_evidence_requires_review"])]
      : result.review_fields,
  };
}
