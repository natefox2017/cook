// Developer: gengyun
// Purpose: Preserve WebVTT text and timed cues for offline, authorized owner-upload evidence.

import { attachAuthorizedMediaEvidence } from "./authorizedMediaEvidence.ts";
import type { MediaEvidenceSegment } from "./authorizedMediaEvidence.ts";
import type { ParsedWebRecipe } from "./schemaRecipe.ts";

const TIMING = /^(\d{2,}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})[ \t]+-->[ \t]+(\d{2,}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})(?:[ \t]+[^\r\n]*)?$/;

function seconds(value: string): number {
  const parts = value.split(":").map(Number);
  const second = parts.pop()!;
  const minute = parts.pop()!;
  if (second >= 60 || minute >= 60) throw new Error("Invalid WebVTT timestamp");
  return (parts.pop() ?? 0) * 3600 + minute * 60 + second;
}

function normalizedText(value: string): string {
  return value.split(/\r?\n/)
    .map((line) => line.replace(/[\t\f\v ]+/g, " ").trim())
    .filter(Boolean).join("\n");
}

function decodeEntities(value: string): string {
  return value.replace(/&(#x[\da-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (entity, name: string) => {
    const lower = name.toLowerCase();
    const named: Record<string, string> = {
      amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
    };
    if (lower in named) return named[lower];
    const codePoint = lower.startsWith("#x")
      ? Number.parseInt(lower.slice(2), 16)
      : Number.parseInt(lower.slice(1), 10);
    return Number.isFinite(codePoint) && codePoint <= 0x10ffff
      ? String.fromCodePoint(codePoint) : entity;
  });
}

// The permissive text mode preserves the existing public-page behavior. Only
// the offline authorized adapter uses strict timed validation and cue budgets.
function readWebVTT(value: string, duration?: number): {
  text: string;
  segments: MediaEvidenceSegment[];
} {
  const strict = duration !== undefined;
  if (strict && (
    typeof value !== "string" || value.length > 100_000 || value.includes("\0") ||
    !/^\uFEFF?WEBVTT(?:[ \t][^\r\n]*)?(?:\r?\n|$)/.test(value) ||
    value.split(/\r?\n/, 1)[0].includes("-->") ||
    !Number.isFinite(duration) || duration <= 0 || duration > 3_600
  )) throw new Error("Invalid or oversized owner WebVTT source");

  const lines = value.replace(/^\uFEFF/, "").split(/\r?\n/);
  const transcript: string[] = [];
  const segments: MediaEvidenceSegment[] = [];
  let skippingBlock = false;
  let header = strict;
  let current: MediaEvidenceSegment | null = null;
  let total = 0;
  const finish = () => {
    if (!current) return;
    current.excerpt = normalizedText(current.excerpt);
    if (strict && (!current.excerpt || current.excerpt.length > 1_500)) {
      throw new Error("Empty or oversized WebVTT cue");
    }
    total += current.excerpt.length;
    if (strict && (segments.length >= 60 || total > 20_000)) {
      throw new Error("WebVTT evidence budget exceeded");
    }
    segments.push(current);
    current = null;
  };

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index].trim();
    if (!line) {
      finish();
      skippingBlock = false;
      header = false;
      continue;
    }
    if ((index === 0 || !strict) && /^WEBVTT(?:[ \t].*)?$/i.test(line)) {
      skippingBlock = false;
      continue;
    }
    if (header) {
      if (line.includes("-->")) throw new Error("Missing WebVTT header separator");
      continue;
    }
    if (/^(?:NOTE(?:[ \t].*)?|STYLE|REGION)$/i.test(line)) {
      if (strict && current) throw new Error("Missing WebVTT cue separator");
      skippingBlock = true;
      continue;
    }
    if (skippingBlock) continue;

    const timing = TIMING.exec(line);
    if (timing) {
      if (strict && current) throw new Error("Missing WebVTT cue separator");
      if (strict) {
        const start = seconds(timing[1]);
        const end = seconds(timing[2]);
        if (!Number.isFinite(start) || !Number.isFinite(end) ||
          end <= start || end > duration! ||
          start < (segments.at(-1)?.startSeconds ?? 0)) {
          throw new Error("Invalid WebVTT cue range");
        }
        current = { kind: "subtitle", excerpt: "", startSeconds: start, endSeconds: end, confidence: null };
      }
      continue;
    }
    // Preserve the former text-only parser's broad timing and cue-ID filtering.
    if (!strict && /\d{2}:\d{2}(?::\d{2})?\.\d{3}\s+-->/.test(line)) continue;
    if (!line.includes("-->") && TIMING.test((lines[index + 1] ?? "").trim())) {
      if (strict && current) throw new Error("Missing WebVTT cue separator");
      continue;
    }
    if (!strict && !line.includes("-->") &&
      /\d{2}:\d{2}(?::\d{2})?\.\d{3}\s+-->/.test(lines[index + 1] ?? "")) continue;
    if (strict && (line.includes("-->") || !current)) {
      throw new Error("Malformed WebVTT cue");
    }
    const cue = decodeEntities(line.replace(/<[^>]*>/g, "")).trim();
    if (cue && transcript.at(-1) !== cue) transcript.push(cue);
    if (current) current.excerpt += (current.excerpt ? "\n" : "") + cue;
  }
  finish();
  if (strict && !segments.length) throw new Error("No timed WebVTT cues");
  return { text: normalizedText(transcript.join("\n")).slice(0, 10_000), segments };
}

export function webVTTText(value: string): string {
  return readWebVTT(value).text;
}

/** Offline-only: the caller has already decoded strict UTF-8 with
 * decodePlainTextArtifact and verified ownership, rights and expiry.
 * No public client authorization, upload endpoint, download or ASR is added.
 */
export function attachOwnerUploadedWebVTT(
  result: ParsedWebRecipe,
  input: { text: string; authorizationReference: string; sourceDurationSeconds: number },
): ParsedWebRecipe {
  return attachAuthorizedMediaEvidence(result, {
    authorizationMethod: "owner_uploaded",
    authorizationReference: input.authorizationReference,
    sourceDurationSeconds: input.sourceDurationSeconds,
    segments: readWebVTT(input.text, input.sourceDurationSeconds).segments,
  });
}
