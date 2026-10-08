// Developer: gengyun
// Purpose: Fetch public HTTPS recipe pages with DNS-pinned connections and strict resource limits.

import { request as httpsRequest } from "node:https";
import type { LookupFunction } from "node:net";
import ipaddr from "ipaddr.js";

export type SafeFetchErrorCode =
  | "FETCH_BLOCKED"
  | "FETCH_TIMEOUT"
  | "MEDIA_TOO_LARGE"
  | "PRIVATE_OR_LOGIN_REQUIRED"
  | "UNSUPPORTED_SOURCE";

export class SafeFetchError extends Error {
  constructor(
    readonly code: SafeFetchErrorCode,
    message: string,
    readonly recoverable = false,
  ) {
    super(message);
    this.name = "SafeFetchError";
  }
}

export interface SafeHTMLPage {
  html: string;
  canonicalURL: string;
  contentType: string;
}

export interface SafeVTTTrack {
  text: string;
  canonicalURL: string;
  contentType: string;
}

interface HTTPResponse {
  status: number;
  headers: Record<string, string | undefined>;
  body: Uint8Array;
}

interface FetchPolicy {
  accept: string;
  contentTypes: readonly string[];
  maxBytes: number;
  timeoutMS: number;
  label: string;
}

interface FetchDependencies {
  resolveIPv4?: (host: string, signal: AbortSignal) => Promise<string[]>;
  request?: (
    url: URL,
    addresses: string[],
    signal: AbortSignal,
    policy: FetchPolicy,
  ) => Promise<HTTPResponse>;
}

const MAX_URL_LENGTH = 8_192;
const MAX_RESPONSE_BYTES = 1_500_000;
const MAX_REDIRECTS = 3;
const TOTAL_TIMEOUT_MS = 10_000;
const TRACK_TIMEOUT_MS = 4_000;
const MAX_TRACK_BYTES = 300_000;
const DNS_TIMEOUT_MS = 2_500;

export function validatePublicHTTPSURL(rawURL: string): URL {
  if (rawURL.length > MAX_URL_LENGTH) {
    throw new SafeFetchError("FETCH_BLOCKED", "The source URL is too long.");
  }

  let url: URL;
  try {
    url = new URL(rawURL);
  } catch {
    throw new SafeFetchError("FETCH_BLOCKED", "The source URL is invalid.");
  }

  const host = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" || url.username || url.password ||
    (url.port && url.port !== "443") || host.endsWith(".") ||
    host.endsWith(".local") || host.endsWith(".internal") ||
    host.endsWith(".localhost") || !host.includes(".") ||
    ipaddr.isValid(host)
  ) {
    throw new SafeFetchError(
      "FETCH_BLOCKED",
      "Only public HTTPS webpage URLs on the default port are supported.",
    );
  }

  // Fragments are client-side only and must not be sent to the remote server.
  url.hash = "";
  return url;
}

export function isPublicAddress(address: string): boolean {
  try {
    const parsed = ipaddr.parse(address);
    return parsed.range() === "unicast";
  } catch {
    return false;
  }
}

async function resolvePublicIPv4(
  host: string,
  signal: AbortSignal,
): Promise<string[]> {
  let addresses: string[];
  try {
    addresses = await Deno.resolveDns(host, "A", { signal });
  } catch (error) {
    if (signal.aborted) {
      throw new SafeFetchError(
        "FETCH_TIMEOUT",
        "The source webpage lookup timed out.",
        true,
      );
    }
    throw new SafeFetchError(
      "FETCH_BLOCKED",
      "The source webpage could not be resolved safely.",
    );
  }

  const uniqueAddresses = [...new Set(addresses)];
  if (
    uniqueAddresses.length === 0 ||
    uniqueAddresses.some((address) => !isPublicAddress(address))
  ) {
    throw new SafeFetchError(
      "FETCH_BLOCKED",
      "The source webpage resolved to a non-public address.",
    );
  }
  return uniqueAddresses;
}

function readHTTPSResponse(
  url: URL,
  addresses: string[],
  signal: AbortSignal,
  policy: FetchPolicy,
): Promise<HTTPResponse> {
  const lookups: LookupFunction = (_host, options, callback) => {
    const results = addresses.map((address) => ({ address, family: 4 }));
    if (options?.all) {
      callback(null, results);
    } else {
      callback(null, results[0].address, results[0].family);
    }
  };

  return new Promise((resolve, reject) => {
    let settled = false;
    const finishError = (error: Error) => {
      if (settled) return;
      settled = true;
      reject(error);
    };

    const request = httpsRequest({
      hostname: url.hostname,
      servername: url.hostname,
      port: 443,
      path: `${url.pathname}${url.search}`,
      method: "GET",
      headers: {
        Accept: policy.accept,
        "Accept-Encoding": "identity",
        "User-Agent": "RecipePouchImport/1.0 (+https://recipepouch.app)",
        Connection: "close",
      },
      lookup: lookups,
      agent: false,
      signal,
    }, (response) => {
      const status = response.statusCode ?? 0;
      const headers: Record<string, string | undefined> = {
        "content-length": response.headers["content-length"],
        "content-type": response.headers["content-type"],
        "content-encoding": response.headers["content-encoding"],
        location: response.headers.location,
      };

      if ([301, 302, 303, 307, 308].includes(status)) {
        response.destroy();
        settled = true;
        resolve({ status, headers, body: new Uint8Array() });
        return;
      }

      if (status === 401 || status === 403 || status === 429) {
        response.destroy();
        finishError(
          new SafeFetchError(
            "PRIVATE_OR_LOGIN_REQUIRED",
            `The ${policy.label} requires access that the import worker does not have.`,
          ),
        );
        return;
      }

      if (status !== 200) {
        response.destroy();
        finishError(
          new SafeFetchError(
            "UNSUPPORTED_SOURCE",
            `The ${policy.label} did not return a readable response.`,
          ),
        );
        return;
      }

      const declaredBytes = Number(headers["content-length"]);
      if (
        Number.isFinite(declaredBytes) && declaredBytes > policy.maxBytes
      ) {
        response.destroy();
        finishError(
          new SafeFetchError(
            "MEDIA_TOO_LARGE",
            `The ${policy.label} exceeds the import size limit.`,
          ),
        );
        return;
      }

      const contentType = (headers["content-type"] ?? "").split(";", 1)[0]
        .trim().toLowerCase();
      if (!policy.contentTypes.includes(contentType)) {
        response.destroy();
        finishError(
          new SafeFetchError(
            "UNSUPPORTED_SOURCE",
            `The source did not return a supported ${policy.label}.`,
          ),
        );
        return;
      }
      const contentEncoding = headers["content-encoding"]?.toLowerCase();
      if (contentEncoding && contentEncoding !== "identity") {
        response.destroy();
        finishError(
          new SafeFetchError(
            "UNSUPPORTED_SOURCE",
            `The ${policy.label} used an unsupported content encoding.`,
          ),
        );
        return;
      }

      const chunks: Uint8Array[] = [];
      let totalBytes = 0;
      response.on("data", (chunk: Uint8Array) => {
        totalBytes += chunk.byteLength;
        if (totalBytes > policy.maxBytes) {
          response.destroy(
            new SafeFetchError(
              "MEDIA_TOO_LARGE",
              `The ${policy.label} exceeds the import size limit.`,
            ),
          );
          return;
        }
        chunks.push(chunk);
      });
      response.on("end", () => {
        if (settled) return;
        settled = true;
        const body = new Uint8Array(totalBytes);
        let offset = 0;
        for (const chunk of chunks) {
          body.set(chunk, offset);
          offset += chunk.byteLength;
        }
        resolve({ status, headers, body });
      });
      response.on("error", (error: Error) => finishError(error));
    });

    request.on("error", (error: Error) => finishError(error));
    request.end();
  });
}

export async function fetchPublicHTML(
  rawURL: string,
  dependencies: FetchDependencies = {},
): Promise<SafeHTMLPage> {
  const response = await fetchPublicResource(
    rawURL,
    {
      accept: "text/html, application/xhtml+xml",
      contentTypes: ["text/html", "application/xhtml+xml"],
      maxBytes: MAX_RESPONSE_BYTES,
      timeoutMS: TOTAL_TIMEOUT_MS,
      label: "source webpage",
    },
    dependencies,
  );
  return {
    html: new TextDecoder("utf-8", { fatal: true }).decode(response.body),
    canonicalURL: response.url.toString(),
    contentType: response.contentType,
  };
}

export async function fetchPublicVTT(
  rawURL: string,
  timeoutMS = TRACK_TIMEOUT_MS,
  dependencies: FetchDependencies = {},
): Promise<SafeVTTTrack> {
  const validatedURL = validatePublicHTTPSURL(rawURL);
  if (!/\.(?:vtt|webvtt)$/i.test(validatedURL.pathname)) {
    throw new SafeFetchError(
      "UNSUPPORTED_SOURCE",
      "Only publicly linked WebVTT caption tracks are supported.",
    );
  }

  const response = await fetchPublicResource(
    validatedURL.toString(),
    {
      accept: "text/vtt, text/plain",
      contentTypes: ["text/vtt", "text/plain"],
      maxBytes: MAX_TRACK_BYTES,
      timeoutMS: Math.min(TRACK_TIMEOUT_MS, timeoutMS),
      label: "caption track",
    },
    dependencies,
  );
  const text = new TextDecoder("utf-8", { fatal: true }).decode(response.body);
  if (!/^\uFEFF?WEBVTT(?:[ \t].*)?(?:\r?\n|$)/.test(text)) {
    throw new SafeFetchError(
      "UNSUPPORTED_SOURCE",
      "The public caption track is not valid WebVTT.",
    );
  }
  return {
    text,
    canonicalURL: response.url.toString(),
    contentType: response.contentType,
  };
}

async function fetchPublicResource(
  rawURL: string,
  policy: FetchPolicy,
  dependencies: FetchDependencies,
): Promise<{ body: Uint8Array; url: URL; contentType: string }> {
  const deadline = Date.now() + policy.timeoutMS;
  let url = validatePublicHTTPSURL(rawURL);

  for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount++) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      throw new SafeFetchError(
        "FETCH_TIMEOUT",
        `The ${policy.label} request timed out.`,
        true,
      );
    }

    const dnsSignal = AbortSignal.timeout(Math.min(DNS_TIMEOUT_MS, remaining));
    const addresses = await (dependencies.resolveIPv4 ?? resolvePublicIPv4)(
      url.hostname,
      dnsSignal,
    );
    if (
      addresses.length === 0 ||
      addresses.some((address) => !isPublicAddress(address))
    ) {
      throw new SafeFetchError(
        "FETCH_BLOCKED",
        `The ${policy.label} resolved to a non-public address.`,
      );
    }

    const requestSignal = AbortSignal.timeout(remaining);
    let response: HTTPResponse;
    try {
      response = await (dependencies.request ?? readHTTPSResponse)(
        url,
        addresses,
        requestSignal,
        policy,
      );
    } catch (error) {
      if (error instanceof SafeFetchError) throw error;
      if (requestSignal.aborted) {
        throw new SafeFetchError(
          "FETCH_TIMEOUT",
          `The ${policy.label} request timed out.`,
          true,
        );
      }
      throw new SafeFetchError(
        "FETCH_BLOCKED",
        `The ${policy.label} connection failed.`,
        true,
      );
    }

    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.location;
      if (!location || redirectCount === MAX_REDIRECTS) {
        throw new SafeFetchError(
          "FETCH_BLOCKED",
          `The ${policy.label} exceeded the safe redirect limit.`,
        );
      }
      let redirectedURL: URL;
      try {
        redirectedURL = new URL(location, url);
      } catch {
        throw new SafeFetchError(
          "FETCH_BLOCKED",
          `The ${policy.label} returned an invalid redirect.`,
        );
      }
      url = validatePublicHTTPSURL(redirectedURL.toString());
      continue;
    }

    if (response.status !== 200) {
      throw new SafeFetchError(
        "UNSUPPORTED_SOURCE",
        `The ${policy.label} did not return a readable response.`,
      );
    }
    if (response.body.byteLength > policy.maxBytes) {
      throw new SafeFetchError(
        "MEDIA_TOO_LARGE",
        `The ${policy.label} exceeds the import size limit.`,
      );
    }
    const contentType = (response.headers["content-type"] ?? "").split(
      ";",
      1,
    )[0]
      .trim().toLowerCase();
    if (!policy.contentTypes.includes(contentType)) {
      throw new SafeFetchError(
        "UNSUPPORTED_SOURCE",
        `The source did not return a supported ${policy.label}.`,
      );
    }
    const contentEncoding = response.headers["content-encoding"]?.toLowerCase();
    if (contentEncoding && contentEncoding !== "identity") {
      throw new SafeFetchError(
        "UNSUPPORTED_SOURCE",
        `The ${policy.label} used an unsupported content encoding.`,
      );
    }
    return {
      body: response.body,
      url,
      contentType: response.headers["content-type"] ?? "text/plain",
    };
  }

  throw new SafeFetchError("FETCH_BLOCKED", "The source URL is not supported.");
}
