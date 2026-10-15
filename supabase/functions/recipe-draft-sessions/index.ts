// Developer: gengyun
// Purpose: Deployable owner-authenticated extractive draft session Edge Function entry point.

import { handleRequest } from "./handler.ts";
import { createRecipeDraftBackendBindings } from "./backendBindings.ts";

// The draft API is default-disabled. The server opts in explicitly with
// RECIPE_DRAFT_SESSIONS_ENABLED=true and every required secret; otherwise the
// backend adapter stays closed and no PostgREST or AI provider traffic occurs.
//
// Commercial usage reservation and cost budgeting (DEV-427) plug into this gate
// once that ledger is merged. Until then the gate fails closed on missing
// configuration instead of fabricating an enabled provider result.
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

// Real trusted adapter: requireUser authenticates the verified JWT, resolveAISecret
// decrypts the server-side provider secret, and the transport talks to the trusted
// Supabase REST endpoint only. The handler maps owner requests to durable draft
// RPCs without ever dispatching a provider.
const dependencies = createRecipeDraftBackendBindings({
  enabled: config.enabled,
  supabaseRESTBaseURL: config.supabaseRESTBaseURL,
  serviceRoleKey: config.serviceRoleKey,
  postgrestTransport: (request) => fetch(request),
  encodedAISecretKey: config.encodedAISecretKey,
  requestTimeoutMs: config.requestTimeoutMs,
}).handlerDependencies;

Deno.serve((request: Request) => handleRequest(request, dependencies));
