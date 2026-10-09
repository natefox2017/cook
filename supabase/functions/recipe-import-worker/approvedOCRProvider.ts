// Developer: gengyun
// Purpose: Enables OCR egress only for an explicitly approved, server-configured HTTPS host.

import {
  OCRArtifactError,
  type OCRPage,
  type OCRProvider,
} from "./artifactOCR.ts";

type ReadEnv = (name: string) => string | undefined;

export function configuredOCRProvider(
  env: ReadEnv = (name) => Deno.env.get(name),
): OCRProvider | null {
  // The default production state is no external OCR: keep source and review.
  if (env("RECIPE_IMPORT_OCR_APPROVED") !== "true") return null;

  const rawURL = env("RECIPE_IMPORT_OCR_PROVIDER_URL");
  const host = env("RECIPE_IMPORT_OCR_APPROVED_HOST")?.toLowerCase();
  const key = env("RECIPE_IMPORT_OCR_API_KEY");
  if (!rawURL || !host || !key) return null;

  let endpoint: URL;
  try {
    endpoint = new URL(rawURL);
  } catch {
    return null;
  }
  if (
    endpoint.protocol !== "https:" ||
    endpoint.username || endpoint.password ||
    (endpoint.port && endpoint.port !== "443") ||
    endpoint.hostname.toLowerCase() !== host ||
    !/^[a-z0-9.-]+$/.test(host) ||
    host === "localhost" || host.endsWith(".local") ||
    host.endsWith(".internal") ||
    /^\d+(?:\.\d+){3}$/.test(host)
  ) return null;

  return {
    async recognize(bytes, controls) {
      let response: Response;
      try {
        response = await fetch(endpoint, {
          method: "POST",
          redirect: "error",
          cache: "no-store",
          headers: {
            "Authorization": `Bearer ${key}`,
            "Content-Type": "application/octet-stream",
            "X-OCR-Content-Type": controls.mimeType,
            "X-OCR-Max-Pages": String(controls.maxPages),
            "X-OCR-Max-Pixels-Per-Page": String(controls.maxPixelsPerPage),
          },
          // Copy only the supplied view into an ArrayBuffer-backed request body.
          body: new Uint8Array(bytes),
          signal: AbortSignal.timeout(controls.timeoutMS),
        });
      } catch {
        throw new OCRArtifactError("OCR_UNAVAILABLE", "Approved OCR request failed.");
      }
      if (!response.ok) {
        throw new OCRArtifactError("OCR_UNAVAILABLE", "Approved OCR provider rejected the request.");
      }
      const length = Number(response.headers.get("content-length") ?? 0);
      if (!response.body || length > 256_000) {
        throw new OCRArtifactError("OCR_INVALID_RESULT", "OCR response exceeded its limit.");
      }

      // A bounded reader prevents untrusted providers from streaming forever.
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let total = 0;
      try {
        while (true) {
          const next = await reader.read();
          if (next.done) break;
          total += next.value.length;
          if (total > 256_000) {
            await reader.cancel();
            throw new OCRArtifactError("OCR_INVALID_RESULT", "OCR response exceeded its limit.");
          }
          chunks.push(next.value);
        }
      } finally {
        reader.releaseLock();
      }
      const combined = new Uint8Array(total);
      let offset = 0;
      for (const part of chunks) {
        combined.set(part, offset);
        offset += part.length;
      }
      let result: unknown;
      try {
        result = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(combined));
      } catch {
        throw new OCRArtifactError("OCR_INVALID_RESULT", "OCR response is not valid JSON.");
      }
      if (
        !result || typeof result !== "object" ||
        !("pages" in result) || !Array.isArray(result.pages)
      ) {
        throw new OCRArtifactError("OCR_INVALID_RESULT", "OCR pages are missing.");
      }
      return result.pages as OCRPage[];
    },
  };
}
