// Developer: gengyun
// Purpose: Bounded owner-scoped media evidence for the import worker. Authorized
//          owner-uploaded WebVTT subtitles are supported today; audio and video
//          fail with an actionable unsupported error while no bounded ASR or
//          keyframe extraction capability exists in Edge.

import { attachOwnerUploadedWebVTT } from "./subtitleEvidence.ts";
import type { ParsedWebRecipe } from "./schemaRecipe.ts";

// Frozen DEV-78 media contract. The WebVTT ceiling is bytes; the audio/video
// ceiling is bytes plus duration, enforced when those routes are reachable.
export const MEDIA_WEBVTT_MAX_BYTES = 1024 * 1024;
export const MEDIA_AUDIO_VIDEO_MAX_BYTES = 20 * 1024 * 1024;
export const MEDIA_MAX_DURATION_SECONDS = 120;

export type MediaKind = "webvtt" | "audio" | "video" | "unsupported";

/** Actionable media failure. The source bytes/artifact are always preserved. */
export class MediaError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly recoverable = false,
  ) {
    super(message);
    this.name = "MediaError";
  }
}

// Mirrors the strict WebVTT header contract used by subtitleEvidence.ts. Only
// WebVTT is in the frozen subtitle contract; SRT and other containers are not.
const VTT_HEADER = /^\uFEFF?WEBVTT(?:[ \t][^\r\n]*)?(?:\r?\n|$)/;
const VTT_TIMING =
  /^(\d{2,}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})[ \t]+-->[ \t]+(\d{2,}:\d{2}:\d{2}\.\d{3}|\d{2}:\d{2}\.\d{3})(?:[ \t]+[^\r\n]*)?$/;

function timestampSeconds(value: string): number {
  const parts = value.split(":").map(Number);
  const second = parts.pop()!;
  const minute = parts.pop()!;
  if (
    !Number.isFinite(second) || !Number.isFinite(minute) ||
    second >= 60 || minute >= 60
  ) {
    throw new MediaError(
      "MEDIA_WEBVTT_INVALID",
      "The WebVTT track has an invalid cue timestamp.",
    );
  }
  return (parts.pop() ?? 0) * 3600 + minute * 60 + second;
}

export function isWebVTTText(value: string): boolean {
  return VTT_HEADER.test(value);
}

/**
 * Server-verifiable duration: the latest cue end time. Client metadata is never
 * trusted and no audio/video container parser is introduced into Edge.
 */
export function webVTTDurationSeconds(text: string): number {
  let latest = 0;
  for (const line of text.split(/\r?\n/)) {
    const match = VTT_TIMING.exec(line);
    if (!match) continue;
    const end = timestampSeconds(match[2]);
    if (end > latest) latest = end;
  }
  return latest;
}

function ascii(bytes: Uint8Array, start: number, length: number): string {
  let out = "";
  for (let index = start; index < start + length && index < bytes.length; index++) {
    out += String.fromCharCode(bytes[index]);
  }
  return out;
}

// Conservative magic-byte signatures. These only classify; they never decode a
// codec, so no media container parser is introduced into the Edge runtime.
function hasID3OrMP3Sync(bytes: Uint8Array): boolean {
  if (bytes.length >= 3 && bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
    return true;
  }
  return bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0;
}

function hasRIFFWAVE(bytes: Uint8Array): boolean {
  return bytes.length >= 12 &&
    ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WAVE";
}

function hasISOBaseBox(bytes: Uint8Array): boolean {
  return bytes.length >= 12 && ascii(bytes, 4, 4) === "ftyp";
}

/**
 * Classifies a media artifact by MIME plus magic bytes. Audio/video is
 * recognized so a caller can fail actionably rather than treating binary media
 * as text. No duration probe is attempted here: container parsing is out of
 * scope for Edge and the worker never loops on unsupported media.
 */
export function classifyMedia(mimeType: string, bytes: Uint8Array): MediaKind {
  const mime = (mimeType || "").split(";", 1)[0].trim().toLowerCase();
  if (mime === "text/vtt" || mime === "text/plain") {
    return "webvtt";
  }
  if (mime.startsWith("audio/")) {
    return hasID3OrMP3Sync(bytes) || hasRIFFWAVE(bytes) || hasISOBaseBox(bytes)
      ? "audio"
      : "unsupported";
  }
  if (mime.startsWith("video/")) {
    return hasISOBaseBox(bytes) ? "video" : "unsupported";
  }
  return "unsupported";
}

/**
 * Actionable unsupported for audio/video: the exact missing capability is named
 * and the original source is preserved for manual entry. It never fabricates
 * text and never retries an unsupported source.
 */
export function unsupportedMediaError(
  kind: MediaKind,
  mimeType: string,
): MediaError {
  if (kind === "audio") {
    return new MediaError(
      "MEDIA_ASR_UNSUPPORTED",
      "Audio transcription needs an approved ASR provider, which is not " +
        "configured. The source is preserved for manual entry.",
    );
  }
  if (kind === "video") {
    return new MediaError(
      "MEDIA_KEYFRAME_UNSUPPORTED",
      "Keyframe extraction and OCR for video are not available in the import " +
        "worker. The source is preserved for manual entry.",
    );
  }
  return new MediaError(
    "MEDIA_UNSUPPORTED_TYPE",
    `The uploaded media type (${mimeType}) is not a supported subtitle, audio, ` +
      "or video format.",
  );
}

/**
 * Authorized owner-uploaded WebVTT vertical route. The caller has already
 * decoded strict UTF-8 via decodePlainTextArtifact and verified ownership,
 * rights and expiry. This only appends timestamped subtitle evidence; it never
 * invents recipe fields or performs ASR/OCR.
 */
export function attachOwnerUploadedMediaEvidence(
  result: ParsedWebRecipe,
  input: { text: string; authorizationReference: string },
): ParsedWebRecipe {
  const bytes = new TextEncoder().encode(input.text);
  if (bytes.byteLength > MEDIA_WEBVTT_MAX_BYTES) {
    throw new MediaError(
      "MEDIA_WEBVTT_TOO_LARGE",
      "The WebVTT caption track exceeds the 1 MiB limit.",
    );
  }
  if (!isWebVTTText(input.text)) {
    throw new MediaError(
      "MEDIA_WEBVTT_INVALID",
      "The uploaded source is not a WebVTT caption track.",
    );
  }
  const duration = webVTTDurationSeconds(input.text);
  if (duration <= 0) {
    throw new MediaError(
      "MEDIA_WEBVTT_NO_CUES",
      "The WebVTT track has no timed cues.",
    );
  }
  try {
    return attachOwnerUploadedWebVTT(result, {
      text: input.text,
      authorizationReference: input.authorizationReference,
      sourceDurationSeconds: duration,
    });
  } catch (error) {
    if (error instanceof MediaError) throw error;
    throw new MediaError(
      "MEDIA_WEBVTT_INVALID",
      error instanceof Error ? error.message : "Invalid WebVTT caption track.",
    );
  }
}
