// Developer: gengyun
// Purpose: Serve the current admin AI provider and usage API contract safely.

import { request as httpsRequest } from "node:https";
import type { LookupFunction } from "node:net";
import ipaddr from "ipaddr.js";
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
  testProvider: (url: URL, apiKey: string) => Promise<boolean>;
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
      return await createProvider(req);
    }
    if (path === "/providers/test" && req.method === "POST") {
      return await testProviderRequest(req, dependencies);
    }
    if (path === "/usage" && req.method === "GET") {
      return await readUsage(req, dependencies.createServiceClient());
    }

    const providerMatch = path.match(/^\/providers\/([^/]+)$/);
    if (providerMatch && req.method === "PUT") {
      return await updateProvider(
        req,
        decodeURIComponent(providerMatch[1]),
        dependencies.createServiceClient(),
      );
    }
    if (providerMatch && req.method === "DELETE") {
      throw new AppError(
        "conflict",
        "Provider deletion is disabled until it has an atomic history guard",
        409,
      );
    }
    if (path.startsWith("/providers") || path === "/usage") {
      throw new AppError("method_not_allowed", "Method is not supported", 405);
    }
    throw new AppError("not_found", "Endpoint not found", 404);
  } catch (error) {
    return errorResponse(error);
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

async function createProvider(req: Request): Promise<Response> {
  const input = parseBody(await readJson(req));
  const provider = parseProviderInput(input);
  if (provider.apiKey) {
    throw unavailable("Provider key encryption is unavailable");
  }
  throw new AppError(
    "conflict",
    "Provider creation is unavailable until the key storage protocol is restored",
    409,
  );
}

async function updateProvider(
  req: Request,
  id: string,
  admin: AdminClient,
): Promise<Response> {
  const provider = parseProviderInput(parseBody(await readJson(req)));
  if (provider.apiKey) {
    throw unavailable("Provider key encryption is unavailable");
  }

  const { data: current, error: currentError } = await admin
    .from("ai_providers")
    .select("id, name, base_url, secret_ref, enabled, updated_at")
    .eq("id", id)
    .maybeSingle();
  if (currentError) throw unavailable("Failed to load provider");
  if (!current) throw new AppError("not_found", "Provider not found", 404);

  const { data: models, error: modelError } = await admin
    .from("ai_models")
    .select(
      "id, provider_id, upstream_model_id, display_name, enabled, created_at",
    )
    .eq("provider_id", id)
    .order("created_at", { ascending: true });
  if (modelError) throw unavailable("Failed to load provider models");
  const currentView = providerView(
    current as ProviderRow,
    models as ModelRow[] ?? [],
  );
  if (provider.model !== currentView.model) {
    throw new AppError(
      "conflict",
      "Model changes are unavailable until an atomic model mapping is restored",
      409,
    );
  }

  const { data: updated, error: updateError } = await admin
    .from("ai_providers")
    .update({
      name: provider.name,
      base_url: provider.baseUrl,
      enabled: provider.active,
    })
    .eq("id", id)
    .select("id, name, base_url, secret_ref, enabled, updated_at")
    .maybeSingle();
  if (updateError) throw unavailable("Failed to update provider");
  if (!updated) throw new AppError("not_found", "Provider not found", 404);
  return json(providerView(updated as ProviderRow, models as ModelRow[] ?? []));
}

async function testProviderRequest(
  req: Request,
  dependencies: AdminAIDependencies,
): Promise<Response> {
  const input = parseBody(await readJson(req));
  const name = typeof input.name === "string" ? input.name.trim() : "";
  const baseUrl = typeof input.baseUrl === "string" ? input.baseUrl.trim() : "";
  const model = typeof input.model === "string" ? input.model.trim() : "";
  const apiKey = typeof input.apiKey === "string" ? input.apiKey : "";
  if (!name || !model || !baseUrl || apiKey.length > 8192) {
    throw new AppError(
      "validation_error",
      "Provider name, URL, and model are required",
      400,
    );
  }
  const url = parseProviderURL(baseUrl, true);
  if (!apiKey) {
    throw unavailable(
      "Testing a saved key is unavailable until its decryption protocol is restored",
    );
  }
  try {
    const ok = await dependencies.testProvider(url, apiKey);
    return json(
      ok ? { ok: true } : { ok: false, message: "Provider check failed" },
    );
  } catch {
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
        "provider_id, model_id, final_model_id, status, latency_ms, input_tokens, output_tokens, created_at",
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

async function probeProvider(url: URL, apiKey: string): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8_000);
  try {
    const addresses = await Deno.resolveDns(url.hostname, "A", {
      signal: controller.signal,
    });
    if (
      !addresses.length ||
      addresses.some((address) => !isPublicAddress(address))
    ) return false;
    const lookup: LookupFunction = (_hostname, options, callback) => {
      const resolved = [...new Set(addresses)].map((address) => ({
        address,
        family: 4,
      }));
      if (options?.all) callback(null, resolved);
      else callback(null, resolved[0].address, resolved[0].family);
    };
    return await new Promise<boolean>((resolve) => {
      const request = httpsRequest({
        hostname: url.hostname,
        servername: url.hostname,
        port: 443,
        path: `${url.pathname.replace(/\/$/, "")}/models`,
        method: "GET",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          Accept: "application/json",
          Connection: "close",
        },
        lookup,
        agent: false,
        signal: controller.signal,
        maxHeaderSize: 16_384,
      }, (response) => {
        response.destroy();
        resolve(
          (response.statusCode ?? 500) >= 200 &&
            (response.statusCode ?? 500) < 300,
        );
      });
      request.on("error", () => resolve(false));
      request.end();
    });
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
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
