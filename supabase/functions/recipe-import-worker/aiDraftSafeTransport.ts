// Developer: gengyun
// Purpose: Bound draft provider POSTs to DNS-pinned verified HTTPS without redirects.
import { request as nativeRequest, type RequestOptions } from "node:https";
import type { ClientRequest, IncomingMessage } from "node:http";
import { isIP, type LookupFunction } from "node:net";
import { isPublicAddress, validatePublicHTTPSURL } from "./safeURLFetch.ts";

type Code =
  | "DISABLED"
  | "INVALID_REQUEST"
  | "BLOCKED"
  | "TIMEOUT"
  | "ABORTED"
  | "REQUEST_TOO_LARGE"
  | "RESPONSE_TOO_LARGE"
  | "UPSTREAM";
export class AIDraftTransportError extends Error {
  code: Code;
  constructor(code: Code) {
    super(`DRAFT_TRANSPORT_${code}`);
    this.code = code;
  }
}
interface Options {
  enabled?: boolean;
  timeoutMs?: number;
  resolveDNS?: (
    hostname: string,
    record: "A" | "AAAA",
    signal: AbortSignal,
  ) => Promise<string[]>;
  requestHTTPS?: typeof nativeRequest;
}
const MAX_BYTES = 65536;
const encoder = new TextEncoder();
const noop = () => {};
function fail(code: Code): never {
  throw new AIDraftTransportError(code);
}
function requireThat(
  value: unknown,
  code: Code = "INVALID_REQUEST",
): asserts value {
  if (!value) fail(code);
}
function declaredLength(
  value: string | undefined | null,
  max: number,
  code: Code,
): number | null {
  if (value === undefined || value === null) return null;
  requireThat(value.length <= 5 && /^(0|[1-9][0-9]*)$/.test(value), code);
  requireThat(BigInt(value) <= BigInt(max), code);
  return Number(value);
}
function defaultNetworkAllowed() {
  // node:https agent:false does not honor managed proxy variables. Never silently bypass them.
  try {
    for (
      const key of [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
      ]
    ) {
      if (Deno.env.get(key)) fail("BLOCKED");
    }
  } catch {
    fail("BLOCKED");
  }
}
async function nativeDNS(
  host: string,
  record: "A" | "AAAA",
  signal: AbortSignal,
): Promise<string[]> {
  return await Deno.resolveDns(host, record, { signal });
}
function pinnedLookup(
  host: string,
  addresses: Array<{ address: string; family: 4 | 6 }>,
): LookupFunction {
  return (name, options, callback) => {
    if (name !== host) {
      callback(new AIDraftTransportError("BLOCKED"), "", 4);
      return;
    }
    const family = options?.family === "IPv4"
      ? 4
      : options?.family === "IPv6"
      ? 6
      : options?.family ?? 0;
    const matches = addresses.filter((item) =>
      !family || item.family === family
    );
    if (![0, 4, 6].includes(family) || matches.length === 0) {
      callback(new AIDraftTransportError("BLOCKED"), "", 4);
      return;
    }
    if (options?.all) callback(null, matches.map((item) => ({ ...item })));
    else callback(null, matches[0].address, matches[0].family);
  };
}

/** DNS/socket hooks exercise the real writer and response reader; they must be trusted test hooks. */
export function createAIDraftSafeTransport(inputOptions: Options = {}) {
  const options = {
    enabled: inputOptions.enabled,
    timeoutMs: inputOptions.timeoutMs,
    resolveDNS: inputOptions.resolveDNS,
    requestHTTPS: inputOptions.requestHTTPS,
  };
  return async (
    request: Request,
    policy: { signal: AbortSignal; maxResponseBytes: number },
  ): Promise<Response> => {
    const started = performance.now();
    if (options.enabled !== true) fail("DISABLED");
    const responseLimit = policy?.maxResponseBytes;
    const callerSignal = policy?.signal;
    const timeout = options.timeoutMs ?? 10000;
    requireThat(
      Number.isSafeInteger(timeout) && timeout >= 1 && timeout <= 10000,
    );
    requireThat(
      request instanceof Request && callerSignal instanceof AbortSignal &&
        Number.isSafeInteger(responseLimit) &&
        responseLimit >= 1 && responseLimit <= MAX_BYTES,
    );
    requireThat(request.method === "POST" && request.redirect === "error");
    let url: URL;
    try {
      requireThat(request.url.length <= 8192, "BLOCKED");
      const raw = new URL(request.url);
      requireThat(!raw.hash && !raw.search, "BLOCKED");
      url = validatePublicHTTPSURL(request.url);
    } catch {
      fail("BLOCKED");
    }
    const names = [...request.headers.keys()];
    requireThat(
      names.every((name) =>
        ["authorization", "accept", "content-type", "content-length"].includes(
          name,
        )
      ),
    );
    const authorization = request.headers.get("authorization") ?? "";
    const match = /^Bearer ([^\r\n]+)$/.exec(authorization);
    requireThat(match && match[1].trim().length > 0 && match[1].length <= 8192);
    requireThat(
      request.headers.get("accept")?.toLowerCase() === "application/json" &&
        request.headers.get("content-type")?.toLowerCase() ===
          "application/json",
    );
    const expectedRequestLength = declaredLength(
      request.headers.get("content-length"),
      MAX_BYTES,
      "REQUEST_TOO_LARGE",
    );
    // Environment access happens only for an enabled default-native call, never on import/factory.
    if (!options.requestHTTPS) defaultNetworkAllowed();
    requireThat(
      !options.resolveDNS || typeof options.resolveDNS === "function",
    );
    requireThat(
      !options.requestHTTPS || typeof options.requestHTTPS === "function",
    );
    const controller = new AbortController();
    const signal = AbortSignal.any([
      request.signal,
      callerSignal,
      controller.signal,
    ]);
    let timedOut = false;
    let closed = false;
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, timeout);
    const deadline = started + timeout;
    const expire = () => {
      if (performance.now() >= deadline && !timedOut) {
        timedOut = true;
        controller.abort();
      }
    };
    const check = () => {
      expire();
      if (closed || signal.aborted) fail(timedOut ? "TIMEOUT" : "ABORTED");
    };
    const abortable = <T>(promise: Promise<T>): Promise<T> =>
      new Promise((resolve, reject) => {
        const abort = () => {
          signal.removeEventListener("abort", abort);
          reject(new AIDraftTransportError(timedOut ? "TIMEOUT" : "ABORTED"));
        };
        signal.addEventListener("abort", abort, { once: true });
        if (signal.aborted) abort();
        promise.then((value) => {
          signal.removeEventListener("abort", abort);
          if (closed || signal.aborted) {
            reject(new AIDraftTransportError(timedOut ? "TIMEOUT" : "ABORTED"));
          } else resolve(value);
        }, () => {
          signal.removeEventListener("abort", abort);
          reject(new AIDraftTransportError("UPSTREAM"));
        });
      });
    try {
      check();
      requireThat(request.body !== null);
      const reader = request.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        while (true) {
          check();
          const chunk = await abortable(reader.read());
          if (chunk.done) break;
          size += chunk.value.byteLength;
          if (size > MAX_BYTES) fail("REQUEST_TOO_LARGE");
          chunks.push(chunk.value);
        }
      } finally {
        try {
          void reader.cancel().catch(noop);
        } catch { /* Best-effort cancellation. */ }
        try {
          reader.releaseLock();
        } catch { /* A late read must not replace the bounded failure. */ }
      }
      requireThat(
        size > 0 &&
          (expectedRequestLength === null || size === expectedRequestLength),
      );
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
      }
      try {
        new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      } catch {
        fail("INVALID_REQUEST");
      }
      check();
      const resolveDNS = options.resolveDNS ?? nativeDNS;
      const families = await abortable(
        Promise.all((["A", "AAAA"] as const).map(async (record) => {
          try {
            return {
              record,
              addresses: await resolveDNS(url.hostname, record, signal),
            };
          } catch (error) {
            if (error instanceof Deno.errors.NotFound) {
              return { record, addresses: [] };
            }
            throw error;
          }
        })),
      );
      check();
      const addresses: Array<{ address: string; family: 4 | 6 }> = [];
      for (const group of families) {
        requireThat(Array.isArray(group.addresses), "BLOCKED");
        const family = group.record === "A" ? 4 : 6;
        for (const address of group.addresses) {
          requireThat(
            typeof address === "string" && isIP(address) === family &&
              isPublicAddress(address),
            "BLOCKED",
          );
          if (!addresses.some((item) => item.address === address)) {
            addresses.push({ address, family });
          }
        }
      }
      requireThat(addresses.length > 0, "BLOCKED");
      check();
      const headers = {
        Authorization: authorization,
        Accept: "application/json",
        "Content-Type": "application/json",
        "Content-Length": String(size),
        "Accept-Encoding": "identity",
        Connection: "close",
      };
      requireThat(
        encoder.encode(
          Object.entries(headers).map(([k, v]) => `${k}: ${v}\r\n`).join(""),
        ).length <= 16384,
      );
      const nativeOptions: RequestOptions = {
        hostname: url.hostname,
        servername: url.hostname,
        port: 443,
        path: url.pathname,
        method: "POST",
        headers,
        lookup: pinnedLookup(url.hostname, addresses),
        agent: false,
        rejectUnauthorized: true,
        maxHeaderSize: 16384,
        signal,
      };
      return await new Promise<Response>((resolve, reject) => {
        let settled = false;
        let outgoing: ClientRequest | undefined;
        let incoming: IncomingMessage | undefined;
        const cleanup = () => {
          signal.removeEventListener("abort", onAbort);
          outgoing?.removeListener("error", onError);
          outgoing?.on("error", noop); // A destroyed native socket may emit a late error.
          incoming?.removeListener("data", onData);
          incoming?.removeListener("end", onEnd);
          incoming?.removeListener("aborted", onError);
          incoming?.removeListener("close", onClose);
          incoming?.removeListener("error", onError);
          incoming?.on("error", noop);
        };
        const rejectOnce = (code: Code) => {
          if (settled) return;
          settled = true;
          cleanup();
          try {
            incoming?.destroy();
          } catch { /* Best-effort native cleanup. */ }
          try {
            outgoing?.destroy();
          } catch { /* Best-effort native cleanup. */ }
          reject(new AIDraftTransportError(code));
        };
        const onError = () => rejectOnce("UPSTREAM");
        const onAbort = () => rejectOnce(timedOut ? "TIMEOUT" : "ABORTED");
        const responseChunks: Uint8Array[] = [];
        let responseSize = 0;
        let expectedResponseLength: number | null = null;
        const onData = (chunk: unknown) => {
          expire();
          if (settled || signal.aborted) {
            try {
              incoming?.destroy();
            } catch {}
            return;
          }
          if (!(chunk instanceof Uint8Array)) {
            rejectOnce("UPSTREAM");
            return;
          }
          responseSize += chunk.byteLength;
          if (responseSize > responseLimit) {
            rejectOnce("RESPONSE_TOO_LARGE");
            return;
          }
          responseChunks.push(new Uint8Array(chunk));
        };
        const onClose = () => {
          if (!settled) rejectOnce("UPSTREAM");
        };
        const onEnd = () => {
          expire();
          if (settled) return;
          if (signal.aborted) {
            onAbort();
            return;
          }
          if (
            expectedResponseLength !== null &&
            responseSize !== expectedResponseLength
          ) {
            rejectOnce("UPSTREAM");
            return;
          }
          const responseBody = new Uint8Array(responseSize);
          let cursor = 0;
          for (const chunk of responseChunks) {
            responseBody.set(chunk, cursor);
            cursor += chunk.byteLength;
          }
          try {
            const status = incoming!.statusCode!;
            if ([204, 205].includes(status) && responseSize > 0) {
              rejectOnce("UPSTREAM");
              return;
            }
            const response = new Response(
              [204, 205].includes(status) ? null : responseBody,
              { status, headers: { "Content-Type": "application/json" } },
            );
            settled = true;
            cleanup();
            resolve(response);
          } catch {
            rejectOnce("UPSTREAM");
          }
        };
        signal.addEventListener("abort", onAbort, { once: true });
        if (signal.aborted) {
          onAbort();
          return;
        }
        try {
          outgoing = (options.requestHTTPS ?? nativeRequest)(
            nativeOptions,
            (response) => {
              expire();
              if (settled || closed || signal.aborted) {
                response.on("error", noop);
                try {
                  response.destroy();
                } catch { /* Late cleanup is best-effort. */ }
                return;
              }
              incoming = response;
              response.on("error", onError);
              response.on("aborted", onError);
              response.on("close", onClose);
              try {
                requireThat(
                  Number.isInteger(response.statusCode) &&
                    response.statusCode! >= 200 && response.statusCode! < 300,
                  "UPSTREAM",
                );
                requireThat(
                  typeof response.headers["content-type"] === "string" &&
                    /^application\/json(?:\s*;|$)/i.test(
                      response.headers["content-type"],
                    ),
                  "UPSTREAM",
                );
                requireThat(
                  !response.headers["content-encoding"] ||
                    response.headers["content-encoding"] === "identity",
                  "UPSTREAM",
                );
                const declared = response.headers["content-length"];
                requireThat(
                  declared === undefined || typeof declared === "string",
                  "UPSTREAM",
                );
                expectedResponseLength = declaredLength(
                  declared,
                  responseLimit,
                  "RESPONSE_TOO_LARGE",
                );
                response.on("data", onData);
                response.on("end", onEnd);
              } catch (error) {
                rejectOnce(
                  error instanceof AIDraftTransportError
                    ? error.code
                    : "UPSTREAM",
                );
              }
            },
          );
          outgoing.on("error", onError);
          if (settled || signal.aborted) {
            try {
              outgoing.destroy();
            } catch { /* Best-effort closed request cleanup. */ }
            return;
          }
          check();
          outgoing.write(bytes);
          if (settled) return;
          check();
          if (settled) return;
          outgoing.end();
        } catch {
          rejectOnce(
            signal.aborted ? timedOut ? "TIMEOUT" : "ABORTED" : "UPSTREAM",
          );
        }
      });
    } catch (error) {
      if (error instanceof AIDraftTransportError) throw error;
      fail(signal.aborted ? timedOut ? "TIMEOUT" : "ABORTED" : "UPSTREAM");
    } finally {
      closed = true;
      clearTimeout(timer);
      controller.abort();
    }
  };
}
