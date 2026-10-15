// Developer: gengyun
// Purpose: Deployable owner-authenticated extractive draft session Edge Function entry point.
//          Wires the DEV-427 ai_edit usage hooks (reserve/fence/mark-generated) around the
//          provider dispatch, dormant by default until the commercial stage is enabled.

import { createServiceClient } from "../_shared/auth.ts";
import { resolveStage } from "../_shared/recipeAccess.ts";
import { handleRequest, type Dependencies } from "./handler.ts";
import { createRecipeDraftBackendBindings } from "./backendBindings.ts";
import { createCommercialDraftDispatcher } from "./commercialDispatch.ts";

// The draft API is default-disabled. The server opts in explicitly with
// RECIPE_DRAFT_SESSIONS_ENABLED=true and every required secret; otherwise the
// backend adapter stays closed and no PostgREST or AI provider traffic occurs.
//
// The commercial usage hooks (DEV-427 reserve/fence/mark-generated) are wired
// only in the commercial release stage; the dormant freeTest default never
// reserves or settles a unit.
function readDraftSessionConfig() {
  const enabled = Deno.env.get("RECIPE_DRAFT_SESSIONS_ENABLED") === "true";
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
  let supabaseRESTBaseURL: URL;
  try {
    supabaseRESTBaseURL = new URL(`${base}/rest/v1`);
  } catch {
    // Placeholder keeps the closed adapter constructible. Because enabled is
    // false above, the adapter never validates or uses this URL.
    supabaseRESTBaseURL = new URL("https://unset.invalid/rest/v1");
  }
  return {
    enabled,
    supabaseRESTBaseURL,
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    encodedAISecretKey: Deno.env.get("COOKAPP_AI_SECRET_KEY_V2") ?? "",
    requestTimeoutMs: 5000,
  };
}

const config = readDraftSessionConfig();
const commercial = resolveStage(
  Deno.env.get("RECIPE_COMMERCIAL_STAGE"),
) === "commercial";

// Real trusted adapter: requireUser authenticates the verified JWT, resolveAISecret
// decrypts the server-side provider secret, and the transport talks to the trusted
// Supabase REST endpoint only. The handler maps owner requests to durable draft
// RPCs without ever dispatching a provider on its own.
const binding = createRecipeDraftBackendBindings({
  enabled: config.enabled,
  supabaseRESTBaseURL: config.supabaseRESTBaseURL,
  serviceRoleKey: config.serviceRoleKey,
  postgrestTransport: (request) => fetch(request),
  encodedAISecretKey: config.encodedAISecretKey,
  requestTimeoutMs: config.requestTimeoutMs,
});

const dependencies: Dependencies = { ...binding.handlerDependencies };
if (config.enabled && commercial) {
  try {
    const admin = createServiceClient();
    const dispatcher = createCommercialDraftDispatcher({
      enabled: config.enabled,
      admin,
      workerDependencies: binding.workerDependencies,
      loadOwnedTurn: binding.handlerDependencies.loadOwnedTurn,
    });
    dependencies.dispatchTurn = dispatcher.dispatchTurn;
  } catch {
    // Missing service role leaves the draft API closed and the hooks unwired.
  }
}

Deno.serve((request: Request) => handleRequest(request, dependencies));
