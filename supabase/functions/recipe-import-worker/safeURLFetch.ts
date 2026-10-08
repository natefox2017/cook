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

interface HTTPResponse {
  status: number;
  headers: Record<string, string | undefined>;
  body: Uint8Array;
}

interface FetchDependencies {
  resolveIPv4?: (host: string, signal: AbortSignal) => Promise<string[]>;
  request?: (
    url: URL,
    addresses: string[],
    signal: AbortSignal,
  ) => Promise<HTTPResponse>;
}

const MAX_URL_LENGTH = 8_192;
const MAX_RESPONSE_BYTES = 1_500_000;
const MAX_REDIRECTS = 3;
const TOTAL_TIMEOUT_MS = 10_000;
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
        Accept: "text/html, application/xhtml+xml",
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
            "The source webpage requires access that the import worker does not have.",
          ),
        );
        return;
      }

      if (status !== 200) {
        response.destroy();
        finishError(
          new SafeFetchError(
            "UNSUPPORTED_SOURCE",
            "The source webpage did not return a readable recipe page.",
          ),
        );
        return;
      }

      const declaredBytes = Number(headers["content-length"]);
      if (
        Number.isFinite(declaredBytes) && declaredBytes > MAX_RESPONSE_BYTES
      ) {
        response.destroy();
        finishError(
          new SafeFetchError(
            "MEDIA_TOO_LARGE",
            "The source webpage exceeds the import size limit.",
          ),
        );
        return;
      }

      const contentType = (headers["content-type"] ?? "").split(";", 1)[0]
        .trim().toLowerCase();
      if (
        contentType !== "text/html" &&
        contentType !== "application/xhtml+xml"
      ) {
        response.destroy();
        finishError(
          new SafeFetchError(
            "UNSUPPORTED_SOURCE",
            "The source URL did not return an HTML webpage.",
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
            "The source webpage used an unsupported content encoding.",
          ),
        );
        return;
      }

      const chunks: Uint8Array[] = [];
      let totalBytes = 0;
      response.on("data", (chunk: Uint8Array) => {
        totalBytes += chunk.byteLength;
        if (totalBytes > MAX_RESPONSE_BYTES) {
          response.destroy(
            new SafeFetchError(
              "MEDIA_TOO_LARGE",
              "The source webpage exceeds the import size limit.",
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
  const deadline = Date.now() + TOTAL_TIMEOUT_MS;
  let url = validatePublicHTTPSURL(rawURL);

  for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount++) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      throw new SafeFetchError(
        "FETCH_TIMEOUT",
        "The source webpage request timed out.",
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
        "The source webpage resolved to a non-public address.",
      );
    }

    const requestSignal = AbortSignal.timeout(remaining);
    let response: HTTPResponse;
    try {
      response = await (dependencies.request ?? readHTTPSResponse)(
        url,
        addresses,
        requestSignal,
      );
    } catch (error) {
      if (error instanceof SafeFetchError) throw error;
      if (requestSignal.aborted) {
        throw new SafeFetchError(
          "FETCH_TIMEOUT",
          "The source webpage request timed out.",
          true,
        );
      }
      throw new SafeFetchError(
        "FETCH_BLOCKED",
        "The source webpage connection failed.",
        true,
      );
    }

    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.location;
      if (!location || redirectCount === MAX_REDIRECTS) {
        throw new SafeFetchError(
          "FETCH_BLOCKED",
          "The source webpage exceeded the safe redirect limit.",
        );
      }
      let redirectedURL: URL;
      try {
        redirectedURL = new URL(location, url);
      } catch {
        throw new SafeFetchError(
          "FETCH_BLOCKED",
          "The source webpage returned an invalid redirect.",
        );
      }
      url = validatePublicHTTPSURL(redirectedURL.toString());
      continue;
    }

    if (response.status !== 200) {
      throw new SafeFetchError(
        "UNSUPPORTED_SOURCE",
        "The source webpage did not return a readable recipe page.",
      );
    }
    if (response.body.byteLength > MAX_RESPONSE_BYTES) {
      throw new SafeFetchError(
        "MEDIA_TOO_LARGE",
        "The source webpage exceeds the import size limit.",
      );
    }
    const contentType = (response.headers["content-type"] ?? "").split(
      ";",
      1,
    )[0]
      .trim().toLowerCase();
    if (
      contentType !== "text/html" && contentType !== "application/xhtml+xml"
    ) {
      throw new SafeFetchError(
        "UNSUPPORTED_SOURCE",
        "The source URL did not return an HTML webpage.",
      );
    }
    const contentEncoding = response.headers["content-encoding"]?.toLowerCase();
    if (contentEncoding && contentEncoding !== "identity") {
      throw new SafeFetchError(
        "UNSUPPORTED_SOURCE",
        "The source webpage used an unsupported content encoding.",
      );
    }
    return {
      html: new TextDecoder("utf-8", { fatal: true }).decode(response.body),
      canonicalURL: url.toString(),
      contentType: response.headers["content-type"] ?? "text/html",
    };
  }

  throw new SafeFetchError("FETCH_BLOCKED", "The source URL is not supported.");
}
