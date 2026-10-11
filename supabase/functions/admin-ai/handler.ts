// Developer: gengyun
// Purpose: Serve the current admin AI provider and usage API contract safely.

import ipaddr from "ipaddr.js";
import {
  type AISecret,
  encryptAISecret,
  resolveAISecret,
} from "../_shared/ai-secret.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { requireAdminSession } from "../_shared/admin-session.ts";
import { requireAdminRole } from "../_shared/admin-role.ts";
import { handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import {
  buildUsageResponse,
  type ModelLabel,
  type ModelRow,
  parseProviderInput,
  parseUsageRange,
  type ProviderRow,
  providerView,
  type UsageEvent,
} from "./model.ts";

const MAX_USAGE_EVENTS = 100_000;
const USAGE_PAGE_SIZE = 1_000;

type AdminSession = Awaited<ReturnType<typeof requireAdminSession>>;
type AdminClient = ReturnType<typeof createServiceClient>;

export interface AdminAIDependencies {
  requireAdminSession: (req: Request) => Promise<AdminSession>;
  createServiceClient: () => AdminClient;
  testProvider: (url: URL, apiKey: string, model: string) => Promise<boolean>;
}

const productionDependencies: AdminAIDependencies = {
  requireAdminSession,
  createServiceClient,
  testProvider: probeProvider,
};

export async function handleRequest(
  req: Request,
  dependencies: AdminAIDependencies = productionDependencies,
): Promise<Response> {
  const cors = handleCors(req, "public");
  if (cors) return cors;

  try {
    const session = await dependencies.requireAdminSession(req);
    requireAdminRole(session.role, ["owner", "admin"]);

    const pathParts = new URL(req.url).pathname.split("/").filter(Boolean);
    const functionIndex = pathParts.findIndex((part) => part === "admin-ai");
    const routeParts = functionIndex >= 0
      ? pathParts.slice(functionIndex + 1)
      : pathParts;
    const path = `/${routeParts.join("/")}`.replace(/\/$/, "") || "/";
    if (path === "/providers" && req.method === "GET") {
      return await listProviders(dependencies.createServiceClient());
    }
    if (path === "/providers" && req.method === "POST") {
      return await saveProvider(req, null, dependencies);
    }
    if (path === "/providers/test" && req.method === "POST") {
      return await testProviderRequest(req, dependencies);
    }
    if (path === "/usage" && req.method === "GET") {
      return await readUsage(req, dependencies.createServiceClient());
    }

    const providerMatch = path.match(/^\/providers\/([^/]+)$/);
    if (providerMatch && req.method === "PUT") {
      return await saveProvider(
        req,
        providerId(decodeURIComponent(providerMatch[1])),
        dependencies,
      );
    }
    if (providerMatch && req.method === "DELETE") {
      const { data, error } = await dependencies.createServiceClient().rpc(
        "admin_ai_delete_provider",
        { p_provider_id: providerId(decodeURIComponent(providerMatch[1])) },
      );
      if (error) throw databaseError(error.code);
      return json(data);
    }
    if (path.startsWith("/providers") || path === "/usage") {
      throw new AppError("method_not_allowed", "Method is not supported", 405);
    }
    throw new AppError("not_found", "Endpoint not found", 404);
  } catch (error) {
    return errorResponse(
      error instanceof AppError
        ? error
        : unavailable("Admin AI request failed"),
    );
  }
}

async function listProviders(admin: AdminClient): Promise<Response> {
  const { data: providers, error: providerError } = await admin
    .from("ai_providers")
    .select("id, name, base_url, secret_ref, enabled, updated_at")
    .order("name", { ascending: true });
  if (providerError) throw unavailable("Failed to load providers");

  const ids = (providers ?? []).map((row) => String(row.id));
  const modelsByProvider = new Map<string, ModelRow[]>();
  if (ids.length) {
    const { data: models, error: modelError } = await admin
      .from("ai_models")
      .select(
        "id, provider_id, upstream_model_id, display_name, enabled, created_at",
      )
      .in("provider_id", ids)
      .order("created_at", { ascending: true });
    if (modelError) throw unavailable("Failed to load provider models");
    for (const model of (models ?? []) as ModelRow[]) {
      const list = modelsByProvider.get(model.provider_id) ?? [];
      list.push(model);
      modelsByProvider.set(model.provider_id, list);
    }
  }

  return json({
    data: ((providers ?? []) as ProviderRow[]).map((provider) =>
      providerView(provider, modelsByProvider.get(provider.id) ?? [])
    ),
  });
}

function providerId(value: string): string {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  ) {
    throw new AppError("validation_error", "Provider ID is invalid", 400);
  }
  return value;
}

function databaseError(code: string): AppError {
  if (code === "PT404") {
    return new AppError("not_found", "Provider not found", 404);
  }
  if (code === "PT409" || code === "23503") {
    return new AppError(
      "conflict",
      "Provider has multiple models, route references, or history references",
      409,
    );
  }
  if (code === "22023") {
    return new AppError("validation_error", "Invalid provider input", 400);
  }
  return unavailable("Provider transaction failed");
}

async function saveProvider(
  req: Request,
  id: string | null,
  dependencies: AdminAIDependencies,
): Promise<Response> {
  const provider = parseProviderInput(parseBody(await readJson(req)));
  if (id === null && !provider.apiKey.trim()) {
    throw new AppError(
      "validation_error",
      "Provider creation requires a key",
      400,
    );
  }
  // A blank edit keeps its opaque legacy reference; only explicit new keys rotate.
  const secret = provider.apiKey.trim()
    ? await encryptAISecret(provider.apiKey)
    : null;
  const { data, error } = await dependencies.createServiceClient().rpc(
    "admin_ai_save_provider",
    {
      p_provider_id: id,
      p_name: provider.name,
      p_base_url: provider.baseUrl,
      p_model: provider.model,
      p_active: provider.active,
      p_secret: secret,
    },
  );
  if (error) throw databaseError(error.code);
  return json(data);
}

async function testProviderRequest(
  req: Request,
  dependencies: AdminAIDependencies,
): Promise<Response> {
  const input = parseBody(await readJson(req));
  let baseUrl: string;
  let model: string;
  let apiKey: string;
  if (typeof input.providerId === "string") {
    const id = providerId(input.providerId);
    const admin = dependencies.createServiceClient();
    const { data: provider, error } = await admin.from("ai_providers")
      .select("id, name, base_url, secret_ref, enabled, updated_at").eq(
        "id",
        id,
      ).maybeSingle();
    if (error) throw unavailable("Failed to load saved provider");
    if (!provider) throw new AppError("not_found", "Provider not found", 404);
    const { data: models, error: modelError } = await admin.from("ai_models")
      .select(
        "id, provider_id, upstream_model_id, display_name, enabled, created_at",
      )
      .eq("provider_id", id).order("created_at", { ascending: true });
    if (modelError) throw unavailable("Failed to load saved model");
    // Caller URL/model/key fields cannot redirect a stored secret to another host.
    baseUrl = provider.base_url;
    model =
      providerView(provider as ProviderRow, models as ModelRow[] ?? []).model;
    if (!provider.secret_ref || !model) {
      throw new AppError(
        "conflict",
        "Saved provider requires a key and model",
        409,
      );
    }
    parseProviderURL(baseUrl, true);
    const { data: secret, error: secretError } = await admin.from("ai_secrets")
      .select("secret_ref, ciphertext, nonce, key_version").eq(
        "secret_ref",
        provider.secret_ref,
      ).maybeSingle();
    if (secretError || !secret) throw unavailable("Saved key is unavailable");
    apiKey = await resolveAISecret(secret as AISecret);
  } else {
    const name = typeof input.name === "string" ? input.name.trim() : "";
    baseUrl = typeof input.baseUrl === "string" ? input.baseUrl.trim() : "";
    model = typeof input.model === "string" ? input.model.trim() : "";
    apiKey = typeof input.apiKey === "string" ? input.apiKey : "";
    if (!name || !model || !baseUrl || !apiKey.trim() || apiKey.length > 8192) {
      throw new AppError(
        "validation_error",
        "Provider name, URL, model, and key are required",
        400,
      );
    }
  }
  const url = parseProviderURL(baseUrl, true);
  try {
    const ok = await dependencies.testProvider(url, apiKey, model);
    return json(
      ok ? { ok: true } : { ok: false, message: "Provider check failed" },
    );
  } catch (error) {
    if (error instanceof ProviderProbeError) {
      return json({ ok: false, message: error.message });
    }
    return json({ ok: false, message: "Provider check failed" });
  }
}

async function readUsage(req: Request, admin: AdminClient): Promise<Response> {
  const range = parseUsageRange(new URL(req.url).searchParams.get("range"));
  const days = Number(range.slice(0, -1));
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const events: UsageEvent[] = [];

  for (let offset = 0; offset < MAX_USAGE_EVENTS; offset += USAGE_PAGE_SIZE) {
    const { data, error } = await admin
      .from("ai_usage_events")
      .select(
        "provider_id, model_id, final_model_id, status, latency_ms, input_tokens, output_tokens, cache_read_input_tokens, created_at",
      )
      .gte("created_at", since)
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(offset, offset + USAGE_PAGE_SIZE - 1);
    if (error) throw unavailable("Failed to load usage events");
    const page = (data ?? []) as UsageEvent[];
    events.push(...page);
    if (page.length < USAGE_PAGE_SIZE) break;
    if (offset + page.length >= MAX_USAGE_EVENTS) {
      throw unavailable("Usage range exceeds the supported event limit");
    }
  }

  const providerIds = [
    ...new Set(
      events.flatMap((event) => event.provider_id ? [event.provider_id] : []),
    ),
  ];
  const modelIds = [
    ...new Set(
      events.flatMap((event) =>
        [event.final_model_id, event.model_id].filter((id): id is string =>
          !!id
        )
      ),
    ),
  ];
  const providerNames = new Map<string, string>();
  const modelLabels = new Map<string, ModelLabel>();
  if (providerIds.length) {
    const { data, error } = await admin.from("ai_providers").select("id, name")
      .in("id", providerIds);
    if (error) throw unavailable("Failed to load provider labels");
    for (const row of data ?? []) {
      providerNames.set(String(row.id), String(row.name));
    }
  }
  if (modelIds.length) {
    const { data, error } = await admin.from("ai_models").select(
      "id, provider_id, upstream_model_id",
    ).in("id", modelIds);
    if (error) throw unavailable("Failed to load model labels");
    for (const row of data ?? []) {
      modelLabels.set(String(row.id), row as ModelLabel);
    }
  }
  return json(buildUsageResponse(events, providerNames, modelLabels));
}

function parseBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new AppError(
      "validation_error",
      "Request body must be a JSON object",
      400,
    );
  }
  return value as Record<string, unknown>;
}

async function readJson(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    throw new AppError(
      "validation_error",
      "Request body must be valid JSON",
      400,
    );
  }
}

function parseProviderURL(raw: string, requireHTTPS: boolean): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new AppError("validation_error", "Provider URL is invalid", 400);
  }
  const unsafeTestHost = requireHTTPS && (
    (url.port && url.port !== "443") || url.hostname.endsWith(".") ||
    url.hostname.endsWith(".local") || url.hostname.endsWith(".internal") ||
    url.hostname.endsWith(".localhost") || !url.hostname.includes(".") ||
    ipaddr.isValid(url.hostname)
  );
  if (
    (requireHTTPS
      ? url.protocol !== "https:"
      : !["http:", "https:"].includes(url.protocol)) ||
    url.username || url.password || url.search || url.hash || unsafeTestHost
  ) {
    throw new AppError(
      "validation_error",
      "Provider URL is not an allowed public endpoint",
      400,
    );
  }
  return url;
}

export class ProviderProbeError extends Error {}

export function providerStatusError(status: number): ProviderProbeError {
  if (status === 401 || status === 403) {
    return new ProviderProbeError(
      `Provider rejected authentication (HTTP ${status}). Check the API key and account permissions.`,
    );
  }
  if (status === 429) {
    return new ProviderProbeError(
      "Provider rate limit reached (HTTP 429). Retry later.",
    );
  }
  return new ProviderProbeError(
    `Provider models endpoint returned HTTP ${status}. Check the API base URL and provider availability.`,
  );
}

async function probeProvider(url: URL, apiKey: string): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8_000);
  let phase = "dns";
  try {
    const addresses = await Deno.resolveDns(url.hostname, "A", {
      signal: controller.signal,
    });
    if (
      !addresses.length ||
      addresses.some((address) => !isPublicAddress(address))
    ) {
      throw new ProviderProbeError(
        "Provider DNS did not resolve exclusively to public addresses. Connection blocked.",
      );
    }
    phase = "https";
    if (/[\r\n]/.test(apiKey)) {
      throw new ProviderProbeError("API key contains invalid characters.");
    }
    const operation = async () => {
      let connection: Deno.Conn | undefined;
      const close = () => {
        try {
          connection?.close();
        } catch { /* Already closed. */ }
      };
      controller.signal.addEventListener("abort", close, { once: true });
      try {
        connection = await Deno.connect({ hostname: addresses[0], port: 443 });
        controller.signal.throwIfAborted();
        // startTls verifies the original hostname while TCP remains pinned to the vetted IP.
        connection = await Deno.startTls(connection as Deno.TcpConn, {
          hostname: url.hostname,
          alpnProtocols: ["http/1.1"],
        });
        controller.signal.throwIfAborted();
        const bytes = new TextEncoder().encode(
          `GET ${
            url.pathname.replace(/\/$/, "")
          }/models HTTP/1.1\r\nHost: ${url.hostname}\r\nAuthorization: Bearer ${apiKey}\r\nAccept: application/json\r\nConnection: close\r\n\r\n`,
        );
        for (let offset = 0; offset < bytes.length;) {
          const written = await connection.write(bytes.subarray(offset));
          if (!written) throw new Error("Connection closed");
          offset += written;
        }
        const status = await readProviderStatus(connection);
        if (status >= 200 && status < 300) return true;
        throw providerStatusError(status);
      } finally {
        close();
        controller.signal.removeEventListener("abort", close);
      }
    };
    return await Promise.race([
      operation(),
      new Promise<never>((_resolve, reject) =>
        controller.signal.addEventListener(
          "abort",
          () =>
            reject(
              new ProviderProbeError(
                "Provider connection timed out after 8 seconds. Retry later.",
              ),
            ),
          { once: true },
        )
      ),
    ]);
  } catch (error) {
    if (error instanceof ProviderProbeError) throw error;
    throw new ProviderProbeError(
      controller.signal.aborted
        ? "Provider connection timed out after 8 seconds. Retry later."
        : phase === "dns"
        ? "Provider DNS lookup failed on the server. Check the hostname and server DNS support."
        : "Provider HTTPS connection failed. Check provider availability and server network access.",
    );
  } finally {
    clearTimeout(timer);
  }
}

export async function readProviderStatus(
  reader: { read(buffer: Uint8Array): Promise<number | null> },
): Promise<number> {
  const buffer = new Uint8Array(8192);
  let length = 0;
  while (length < buffer.length) {
    const count = await reader.read(buffer.subarray(length));
    if (!count) break;
    length += count;
    const text = new TextDecoder().decode(buffer.subarray(0, length));
    const end = text.indexOf("\r\n");
    if (end >= 0) {
      const match = /^HTTP\/1\.[01] ([1-5][0-9]{2})(?: |$)/.exec(
        text.slice(0, end),
      );
      if (!match) break;
      return Number(match[1]);
    }
  }
  throw new ProviderProbeError(
    "Provider returned an invalid or oversized HTTP status line.",
  );
}

function isPublicAddress(address: string): boolean {
  try {
    return ipaddr.parse(address).range() === "unicast";
  } catch {
    return false;
  }
}

function unavailable(message: string): AppError {
  return new AppError("server_misconfigured", message, 503);
}
