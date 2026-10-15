// Developer: gengyun
// Purpose: Wire the verified-owner recipe translation handler to real Supabase reads, the phase-II
//          internal usage RPCs, and the safe provider over the verified HTTPS transport. The service
//          key never leaves Edge; every owned read carries the owner predicate and the endpoint is
//          closed-by-default (explicit env + commercial stage + premium reserve gate).

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { type AISecret, resolveAISecret } from "../_shared/ai-secret.ts";
import { parseProviderInput } from "../admin-ai/model.ts";
import { createAIDraftSafeTransport } from "../recipe-import-worker/aiDraftSafeTransport.ts";
import {
  finalizeInternal,
  type InternalCapability,
  type InternalSource,
  markDispatchedInternal,
  releaseInternal,
  reserveInternal,
} from "../_shared/recipeInternalUsage.ts";
import {
  handleRequest,
  type Dependencies,
} from "./handler.ts";

type Row = Record<string, unknown>;

const ROUTE_KEY = "recipe_translation_v1";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const MAX_RESPONSE_BYTES = 65_536;
const MAX_CONTENT_BYTES = 32_768;
const encoder = new TextEncoder();

/** Closed-by-default: the endpoint is off unless explicitly enabled by operations. */
function enabled(): boolean {
  return Deno.env.get("RECIPE_TRANSLATION_ENABLED") === "true";
}

// Mirrors _shared/recipeAccess.ts resolveStage; freeTest is the dormant default.
function stage(): "freeTest" | "commercial" {
  return Deno.env.get("RECIPE_COMMERCIAL_STAGE") === "commercial"
    ? "commercial"
    : "freeTest";
}

async function loadRouteConfiguration(admin: SupabaseClient) {
  const { data: route, error: routeError } = await admin
    .from("ai_routes")
    .select(
      "route_key,primary_model_id,enabled,timeout_ms,max_retries,max_output_tokens,temperature",
    )
    .eq("route_key", ROUTE_KEY)
    .eq("enabled", true)
    .maybeSingle();
  if (
    routeError || !route || route.enabled !== true ||
    !UUID.test(route.primary_model_id ?? "")
  ) {
    return null;
  }
  const { data: model, error: modelError } = await admin
    .from("ai_models")
    .select("id,provider_id,upstream_model_id,display_name,enabled,created_at")
    .eq("id", route.primary_model_id)
    .eq("enabled", true)
    .maybeSingle();
  if (modelError || !model || model.enabled !== true) return null;
  const { data: provider, error: providerError } = await admin
    .from("ai_providers")
    .select("id,name,base_url,secret_ref,enabled,updated_at")
    .eq("id", model.provider_id)
    .eq("enabled", true)
    .maybeSingle();
  if (
    providerError || !provider || provider.enabled !== true ||
    typeof provider.secret_ref !== "string" ||
    provider.secret_ref.length === 0 ||
    provider.secret_ref.length > 512
  ) {
    return null;
  }
  return { route, model, provider };
}

export function createRecipeTranslationDependencies(
  admin: SupabaseClient,
): Dependencies {
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(name, args);
    if (error) {
      console.error("recipe_translation_rpc_failed", {
        rpc: name,
        code: error.code,
      });
      throw new Error("recipe_translation_rpc_failed");
    }
    return (data as Record<string, unknown>) ?? {};
  };

  const translate: Dependencies["translate"] = async (prompt, signal) => {
    const config = await loadRouteConfiguration(admin);
    if (!config) throw new Error("TRANSLATION_PROVIDER_DISABLED");

    let parsed: { baseUrl: string; model: string };
    try {
      parsed = parseProviderInput({
        name: config.provider.name,
        baseUrl: config.provider.base_url,
        model: config.model.upstream_model_id,
        apiKey: "",
        active: true,
      });
    } catch {
      throw new Error("TRANSLATION_PROVIDER_DISABLED");
    }
    if (new URL(parsed.baseUrl).protocol !== "https:") {
      throw new Error("TRANSLATION_PROVIDER_DISABLED");
    }

    const { data: secretRow, error: secretError } = await admin
      .from("ai_secrets")
      .select("secret_ref,ciphertext,nonce,key_version")
      .eq("secret_ref", config.provider.secret_ref)
      .maybeSingle();
    if (
      secretError || !secretRow || typeof secretRow.ciphertext !== "string" ||
      typeof secretRow.nonce !== "string"
    ) {
      throw new Error("TRANSLATION_PROVIDER_SECRET");
    }

    const transport = createAIDraftSafeTransport({
      enabled: true,
      timeoutMs: Number.isSafeInteger(config.route.timeout_ms)
        ? (config.route.timeout_ms as number)
        : 60_000,
    });

    const body = JSON.stringify({
      model: parsed.model,
      stream: false,
      max_tokens: Number.isSafeInteger(config.route.max_output_tokens)
        ? (config.route.max_output_tokens as number)
        : 4_096,
      ...(config.route.temperature == null
        ? {}
        : { temperature: config.route.temperature }),
      response_format: { type: "json_object" },
      messages: [{ role: "user", content: prompt }],
    });
    if (encoder.encode(body).length > 65_536) {
      throw new Error("TRANSLATION_PROVIDER_INPUT_BUDGET");
    }

    let key: string;
    try {
      const secret: AISecret = {
        secret_ref: config.provider.secret_ref,
        ciphertext: secretRow.ciphertext,
        nonce: secretRow.nonce,
        key_version: secretRow.key_version,
      };
      key = await resolveAISecret(secret);
    } catch {
      throw new Error("TRANSLATION_PROVIDER_SECRET");
    }
    if (!key || key.length > 8_192 || /[\r\n]/.test(key)) {
      throw new Error("TRANSLATION_PROVIDER_SECRET");
    }

    let response: Response;
    try {
      const request = new Request(
        `${parsed.baseUrl.replace(/\/$/, "")}/chat/completions`,
        {
          method: "POST",
          redirect: "error",
          signal,
          headers: {
            Authorization: `Bearer ${key}`,
            Accept: "application/json",
            "Content-Type": "application/json",
          },
          body,
        },
      );
      response = await transport(request, {
        signal,
        maxResponseBytes: MAX_RESPONSE_BYTES,
      });
    } catch {
      throw new Error("TRANSLATION_PROVIDER_UNAVAILABLE");
    }

    if (
      response.status < 200 || response.status >= 300 ||
      !/^application\/json(?:\s*;|$)/i.test(
        response.headers.get("content-type") ?? "",
      )
    ) {
      await response.body?.cancel().catch(() => undefined);
      throw new Error("TRANSLATION_PROVIDER_RESPONSE");
    }

    let envelope: Row;
    try {
      envelope = await readBoundedProviderJSON(response, signal);
    } catch {
      throw new Error("TRANSLATION_PROVIDER_RESPONSE");
    }

    const choices = envelope.choices;
    if (!Array.isArray(choices) || choices.length !== 1) {
      throw new Error("TRANSLATION_PROVIDER_RESPONSE");
    }
    const choice = choices[0] as Row;
    const message = choice && typeof choice === "object" ? choice.message as Row : null;
    if (
      !choice || choice.finish_reason !== "stop" ||
      !message || message.role !== "assistant" ||
      typeof message.content !== "string" ||
      [...message.content].length > MAX_CONTENT_BYTES ||
      encoder.encode(message.content).length > MAX_CONTENT_BYTES
    ) {
      throw new Error("TRANSLATION_PROVIDER_RESPONSE");
    }

    let content: unknown;
    try {
      content = JSON.parse(message.content);
    } catch {
      throw new Error("TRANSLATION_PROVIDER_RESPONSE");
    }
    return content;
  };

  return {
    verifiedOwner: async (request) => {
      const { user } = await requireUser(request);
      return { id: user.id, isAnonymous: user.is_anonymous ?? false };
    },
    isEnabled: enabled,
    stage: stage(),
    loadOwnedRecipe: async (owner, recipeID) => {
      // The V1 canonical recipe store is the whole-library user_snapshots payload, not the legacy
      // public.recipes table. Resolve only the owner's recipe id + per-recipe updatedAt; the full
      // recipe content is never read or returned here.
      const { data, error } = await admin
        .from("user_snapshots")
        .select("payload")
        .eq("user_id", owner)
        .maybeSingle();
      if (error) {
        console.error("recipe_translation_snapshot_read_failed", {
          code: error.code,
        });
        throw new Error("recipe_translation_snapshot_read_failed");
      }
      if (!data || typeof data !== "object" || Array.isArray(data)) return null;
      const payload = (data as Row).payload;
      if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
        return null;
      }
      const recipes = (payload as Row).recipes;
      if (!Array.isArray(recipes)) return null;
      for (const item of recipes) {
        if (item === null || typeof item !== "object" || Array.isArray(item)) {
          continue;
        }
        const recipe = item as Row;
        if (typeof recipe.id !== "string" || recipe.id.toLowerCase() !== recipeID) {
          continue;
        }
        if (typeof recipe.updatedAt !== "string") return null;
        return { id: recipe.id, updatedAt: recipe.updatedAt };
      }
      return null;
    },
    loadFinalizedResult: async (owner, capability, inputHash) => {
      // Recover the durable proposal for a committed reservation replay. The finalization row is
      // unique on (owner, capability, input_hash), so a committed reservation has exactly one.
      const { data, error } = await admin
        .from("recipe_usage_finalizations")
        .select("payload")
        .eq("owner_id", owner)
        .eq("capability", capability)
        .eq("input_hash", inputHash)
        .maybeSingle();
      if (error) {
        console.error("recipe_translation_finalized_read_failed", {
          code: error.code,
        });
        throw new Error("recipe_translation_finalized_read_failed");
      }
      if (!data || typeof data !== "object" || Array.isArray(data)) return null;
      const payload = (data as Row).payload;
      if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
        return null;
      }
      return payload as Row;
    },
    translate,
    reserve: (
      owner,
      operationID,
      capability: InternalCapability,
      inputHash,
      source: InternalSource,
    ) =>
      reserveInternal(rpc, owner, operationID, capability, inputHash, source),
    markDispatched: (owner, operationID) =>
      markDispatchedInternal(rpc, owner, operationID),
    finalize: (
      owner,
      operationID,
      capability: InternalCapability,
      inputHash,
      source: InternalSource,
      payloadHash,
      payload,
      resultID,
    ) =>
      finalizeInternal(
        rpc,
        owner,
        operationID,
        capability,
        inputHash,
        source,
        null,
        payloadHash,
        payload,
        "translation",
        resultID,
      ),
    release: (owner, operationID) => releaseInternal(rpc, owner, operationID),
  };
}

async function readBoundedProviderJSON(
  response: Response,
  signal: AbortSignal,
): Promise<Row> {
  if (!response.body) throw new Error("empty body");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_RESPONSE_BYTES) throw new Error("too large");
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("not an object");
  }
  return parsed as Row;
}

Deno.serve(async (request: Request) => {
  let admin: SupabaseClient;
  try {
    admin = createServiceClient();
  } catch {
    return Response.json(
      {
        code: "TRANSLATION_DISABLED",
        message: "Recipe translation is not available.",
        recoverable: true,
        request_id: crypto.randomUUID(),
      },
      { status: 503 },
    );
  }
  return handleRequest(request, createRecipeTranslationDependencies(admin));
});
