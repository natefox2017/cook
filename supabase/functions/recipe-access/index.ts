// Developer: gengyun
// Purpose: Wire the verified-owner commercial access snapshot to the server-owned ledger RPC.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { POLICY } from "../_shared/recipeAccessContract.mjs";
import { resolveStage } from "../_shared/recipeAccess.ts";
import { Failure, handleRequest, type Dependencies } from "./handler.ts";

export function createRecipeAccessDependencies(
  admin: SupabaseClient,
): Dependencies {
  return {
    verifiedOwner: async (request) => {
      const { user } = await requireUser(request);
      return { id: user.id, isAnonymous: user.is_anonymous ?? false };
    },
    policyVersion: POLICY.schemaVersion,
    stage: resolveStage(Deno.env.get("RECIPE_COMMERCIAL_STAGE")),
    rpc: async (name, args) => {
      const { data, error } = await admin.rpc(name, args);
      if (error) {
        console.error("recipe_access_rpc_failed", { code: error.code });
        throw new Failure("SERVICE_UNAVAILABLE");
      }
      return (data as Record<string, unknown>) ?? {};
    },
  };
}

Deno.serve(async (request: Request) => {
  let admin: SupabaseClient;
  try {
    admin = createServiceClient();
  } catch {
    return Response.json(
      {
        code: "SERVICE_UNAVAILABLE",
        message: "The commerce service is temporarily unavailable.",
        recoverable: true,
        request_id: crypto.randomUUID(),
      },
      { status: 503 },
    );
  }
  return handleRequest(request, createRecipeAccessDependencies(admin));
});
