// Developer: gengyun
// Purpose: Deployable owner-authenticated composition root for the recipe edit proposal modules. It
// wires the real OpenAI-compatible provider (route/model/provider config + secret + bounded transport)
// and the real DEV-427 usage ledger port; both fail closed when configuration is missing.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { createServiceClient } from "../_shared/auth.ts";
import { resolveAISecret, type AISecret } from "../_shared/ai-secret.ts";
import { createAIDraftSafeTransport } from "../recipe-import-worker/aiDraftSafeTransport.ts";
import { createRecipeEditBindings } from "./backendBindings.ts";
import { handleRequest, type EditProviderPort } from "./handler.ts";
import { createRecipeEditProvider } from "./provider.ts";
import { createLedgerUsagePort } from "./usagePort.ts";

const EDIT_ROUTE_KEY = "recipe_edit_v1";

function restBaseURL(): URL | null {
  const raw = Deno.env.get("SUPABASE_URL");
  if (!raw) return null;
  try {
    return new URL(`${raw.replace(/\/+$/, "")}/rest/v1`);
  } catch {
    return null;
  }
}

async function loadEditRoute(
  client: SupabaseClient,
): Promise<{
  route: Parameters<typeof createRecipeEditProvider>[0]["route"];
  model: Parameters<typeof createRecipeEditProvider>[0]["model"];
  provider: Parameters<typeof createRecipeEditProvider>[0]["provider"];
} | null> {
  const { data: route, error: routeError } = await client
    .from("ai_routes")
    .select(
      "route_key,primary_model_id,enabled,timeout_ms,max_retries,max_output_tokens,temperature",
    )
    .eq("route_key", EDIT_ROUTE_KEY)
    .eq("enabled", true)
    .single();
  if (routeError || !route || !route.primary_model_id) return null;
  const { data: model, error: modelError } = await client
    .from("ai_models")
    .select("id,provider_id,upstream_model_id,display_name,enabled,created_at")
    .eq("id", route.primary_model_id)
    .eq("enabled", true)
    .single();
  if (modelError || !model || model.enabled !== true) return null;
  const { data: provider, error: providerError } = await client
    .from("ai_providers")
    .select("id,name,base_url,secret_ref,enabled,updated_at")
    .eq("id", model.provider_id)
    .eq("enabled", true)
    .single();
  if (providerError || !provider || typeof provider.secret_ref !== "string") return null;
  return {
    route: route as Parameters<typeof createRecipeEditProvider>[0]["route"],
    model: model as Parameters<typeof createRecipeEditProvider>[0]["model"],
    provider: provider as Parameters<typeof createRecipeEditProvider>[0]["provider"],
  };
}

Deno.serve(async (request: Request): Promise<Response> => {
  const base = restBaseURL();
  const enabled = Deno.env.get("RECIPE_EDIT_PROPOSALS_ENABLED") === "true" &&
    base !== null &&
    (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").length > 0;

  let provider: EditProviderPort | undefined;
  let usage = undefined;
  try {
    const client = createServiceClient();
    const route = await loadEditRoute(client);
    if (enabled && route) {
      const { data: secrets, error: secretError } = await client
        .from("ai_secrets")
        .select("secret_ref,ciphertext,nonce,key_version")
        .eq("secret_ref", route.provider.secret_ref)
        .single();
      if (!secretError && secrets) {
        const apiKey = await resolveAISecret(secrets as AISecret);
        const transport = createAIDraftSafeTransport({ enabled: true });
        const providerFactory = createRecipeEditProvider({
          ...route,
          enabled: true,
          resolveSecret: async () => apiKey,
          transport,
        });
        provider = { generate: (input) => providerFactory(input) };
      }
    }
    usage = createLedgerUsagePort(async (name, args) => {
      const { data, error } = await client.rpc(name, args);
      if (error) throw error;
      return (data as Record<string, unknown>) ?? {};
    });
  } catch {
    // Provider/usage wiring failures leave the ports fail-closed; the handler maps them to 503.
    provider = undefined;
    usage = undefined;
  }

  const deps = createRecipeEditBindings({
    enabled,
    supabaseRESTBaseURL: base ??
      new URL("https://unconfigured.invalid/rest/v1"),
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    postgrestTransport: (request, policy) =>
      fetch(request, { signal: policy.signal }),
    provider,
    usage,
  });
  return handleRequest(request, deps);
});
