// Developer: gengyun
// Purpose: Approved, host-pinned, bounded OpenAI-compatible translation egress.

import { AppError } from "../_shared/errors.ts";

const MAX_RESPONSE_BYTES = 64 * 1024;

export type TranslationProvider = (
  prompt: string,
  signal: AbortSignal,
) => Promise<unknown>;

function approvedHost(host: string): boolean {
  if (!/^[a-z0-9.-]+$/.test(host)) return false;
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal")) return false;
  if (/^\d+(?:\.\d+){3}$/.test(host)) return false;
  return true;
}

function providerError(): AppError {
  return new AppError("internal_error", "Translation provider rejected the request.", 502);
}

function parseProviderJSON(raw: unknown): unknown {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw providerError();
  }
  const body = raw as { choices?: Array<{ message?: { content?: unknown } }> };
  const content = body.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw providerError();
  }
  // The prompt requires bare JSON, but tolerate one surrounding code fence.
  const stripped = content.trim().replace(/^```(?:json)?\s*|\s*```$/g, "");
  try {
    return JSON.parse(stripped);
  } catch {
    throw providerError();
  }
}

/**
 * Reads provider configuration from environment using the same approved-host
 * posture as OCR: HTTPS-only, exact host pin, no userinfo, no non-443 port,
 * no loopback/internal/IP hosts. The default state is no external translation.
 */
export function configuredTranslationProvider(
  env: (name: string) => string | undefined = (name) => Deno.env.get(name),
): TranslationProvider | null {
  const rawURL = env("TRANSLATION_PROVIDER_URL");
  const host = env("TRANSLATION_PROVIDER_APPROVED_HOST")?.toLowerCase();
  const key = env("TRANSLATION_PROVIDER_API_KEY");
  const model = env("TRANSLATION_PROVIDER_MODEL");
  if (!rawURL || !host || !key || !model) return null;

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
    !approvedHost(host)
  ) {
    return null;
  }

  return async (prompt, signal) => {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${key}`,
      },
      // Never follow a redirect: the approved host is the only allowed egress.
      redirect: "error",
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: prompt }],
        temperature: 0,
      }),
      signal,
    });
    if (!response.ok) {
      throw providerError();
    }
    const declaredLength = Number(response.headers.get("content-length") ?? 0);
    if (!response.body || declaredLength > MAX_RESPONSE_BYTES) {
      throw providerError();
    }

    // A bounded reader prevents untrusted providers from streaming forever.
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.byteLength;
        if (total > MAX_RESPONSE_BYTES) {
          await reader.cancel().catch(() => undefined);
          throw providerError();
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }

    const combined = new Uint8Array(total);
    let offset = 0;
    for (const part of chunks) {
      combined.set(part, offset);
      offset += part.byteLength;
    }
    return parseProviderJSON(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(combined)));
  };
}
