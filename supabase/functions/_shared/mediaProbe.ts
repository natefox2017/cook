// Developer: gengyun
// Purpose: Bounded, fail-closed server-side media validation for the DEV-78 finite
//          media contract. Verifies container magic-byte signatures for
//          mp3/m4a/wav/mp4 and an authoritative WAV duration. MP3/MP4/M4A duration
//          is never estimated from bitrate and is reported unverifiable until a
//          maintained probe exists, so unverifiable media is always rejected.

export const MEDIA_AUDIO_VIDEO_MAX_BYTES = 20 * 1024 * 1024;
export const MEDIA_MAX_DURATION_SECONDS = 120;

// Frozen DEV-78 media containers. SRT and other caption containers are out of
// scope; WebVTT rides the existing text/plain upload path.
export const SUPPORTED_MEDIA_TYPES: Readonly<Record<string, true>> = {
  "audio/mpeg": true,
  "audio/mp3": true,
  "audio/mp4": true,
  "audio/x-m4a": true,
  "audio/m4a": true,
  "audio/wav": true,
  "audio/x-wav": true,
  "video/mp4": true,
};

export interface MediaUploadFailure {
  code: string;
  message: string;
}

function ascii(bytes: Uint8Array, start: number, length: number): string {
  let out = "";
  for (
    let index = start;
    index < start + length && index < bytes.length;
    index++
  ) {
    out += String.fromCharCode(bytes[index]);
  }
  return out;
}

function readU32LE(bytes: Uint8Array, offset: number): number {
  if (offset + 4 > bytes.length) return 0;
  return (
    (bytes[offset] | (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0
  );
}

function hasWAVSignature(bytes: Uint8Array): boolean {
  return bytes.length >= 12 &&
    ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WAVE";
}

function hasMP3Signature(bytes: Uint8Array): boolean {
  if (bytes.length >= 3 && bytes[0] === 0x49 && bytes[1] === 0x44 &&
    bytes[2] === 0x33) {
    return true;
  }
  return bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0;
}

function hasMP4Signature(bytes: Uint8Array): boolean {
  return bytes.length >= 12 && ascii(bytes, 4, 4) === "ftyp";
}

/** Authoritative RIFF/WAVE duration: byte rate over data chunk size. */
function probeWAVDuration(bytes: Uint8Array): number | null {
  if (!hasWAVSignature(bytes)) return null;
  let byteRate: number | null = null;
  let dataSize: number | null = null;
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const chunkID = ascii(bytes, offset, 4);
    const chunkSize = readU32LE(bytes, offset + 4);
    if (chunkSize > bytes.length - offset - 8) return null;
    if (chunkID === "fmt ") {
      // fmt payload: audioFormat(2) channels(2) sampleRate(4) byteRate(4).
      if (chunkSize < 16) return null;
      byteRate = readU32LE(bytes, offset + 8 + 8);
    } else if (chunkID === "data") {
      dataSize = chunkSize;
    }
    offset += 8 + chunkSize + (chunkSize % 2);
  }
  if (byteRate === null || dataSize === null || byteRate <= 0) return null;
  return dataSize / byteRate;
}

/**
 * Duration in seconds, or null when it cannot be authoritatively verified.
 * Only WAV is verifiable in Edge today; MP3/MP4/M4A require a maintained
 * decoder and are never estimated from a first-frame bitrate.
 */
export function probeMediaDuration(
  mimeType: string,
  bytes: Uint8Array,
): number | null {
  const mime = (mimeType || "").split(";", 1)[0].trim().toLowerCase();
  if (mime === "audio/wav" || mime === "audio/x-wav") {
    return probeWAVDuration(bytes);
  }
  return null;
}

/**
 * Owner-scoped media upload verification: MIME whitelist, container signature,
 * and a verifiable duration within the frozen 120s bound. Returns null when the
 * upload is valid, else a MediaUploadFailure. Never trusts client metadata and
 * never accepts a source whose duration cannot be verified server-side.
 */
export function verifyMediaUpload(
  mimeType: string,
  bytes: Uint8Array,
): MediaUploadFailure | null {
  const mime = (mimeType || "").split(";", 1)[0].trim().toLowerCase();
  if (SUPPORTED_MEDIA_TYPES[mime] !== true) {
    return {
      code: "MEDIA_UNSUPPORTED_TYPE",
      message: `The uploaded media type (${mimeType || "unknown"}) is not supported.`,
    };
  }
  const signatureMatches =
    mime === "audio/wav" || mime === "audio/x-wav"
      ? hasWAVSignature(bytes)
      : mime === "audio/mpeg" || mime === "audio/mp3"
      ? hasMP3Signature(bytes)
      : hasMP4Signature(bytes);
  if (!signatureMatches) {
    return {
      code: "MEDIA_INVALID_SIGNATURE",
      message: "The uploaded bytes do not match the declared media type.",
    };
  }
  const duration = probeMediaDuration(mime, bytes);
  if (duration === null) {
    return {
      code: "MEDIA_DURATION_UNAVAILABLE",
      message: "The media duration could not be verified server-side; the " +
        "source is preserved for manual entry.",
    };
  }
  if (duration > MEDIA_MAX_DURATION_SECONDS) {
    return {
      code: "MEDIA_TOO_LONG",
      message: `The media exceeds the ${MEDIA_MAX_DURATION_SECONDS}s limit.`,
    };
  }
  return null;
}
