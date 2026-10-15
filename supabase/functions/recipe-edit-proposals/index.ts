// Developer: gengyun
// Purpose: Deployable owner-authenticated composition root for the recipe edit proposal modules.
//
// Trusted configuration (never committed, never logged):
//   SUPABASE_URL                    — project REST origin (e.g. https://<ref>.supabase.co)
//   SUPABASE_SERVICE_ROLE_KEY       — service role for PostgREST reads and edit-proposal RPCs
//   SUPABASE_ANON_KEY               — anon key used by requireUser for JWT verification
// Optional feature switch:
//   RECIPE_EDIT_PROPOSALS_ENABLED   — "true" enables the endpoint (dormant freeTest default stays
//                                     closed until the owner wires provider config and usage ledger)
//
// The provider and commercial usage ports are owner handoff; until then generation and settlement
// fail closed (503) instead of faking a provider result or a settlement.

import { createRecipeEditBindings } from "./backendBindings.ts";
import { handleRequest } from "./handler.ts";

function restBaseURL(): URL | null {
  const raw = Deno.env.get("SUPABASE_URL");
  if (!raw) return null;
  try {
    return new URL(`${raw.replace(/\/+$/, "")}/rest/v1`);
  } catch {
    return null;
  }
}

Deno.serve((request: Request): Promise<Response> => {
  const base = restBaseURL();
  const enabled = Deno.env.get("RECIPE_EDIT_PROPOSALS_ENABLED") === "true" &&
    base !== null &&
    (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").length > 0;
  const deps = createRecipeEditBindings({
    enabled,
    supabaseRESTBaseURL: base ??
      new URL("https://unconfigured.invalid/rest/v1"),
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    postgrestTransport: (request, policy) =>
      fetch(request, { signal: policy.signal }),
  });
  return handleRequest(request, deps);
});
