// Developer: gengyun
// Purpose: Wire the verified-owner commercial usage handler to real Supabase reads and ledger RPCs.
// The service key never leaves Edge; every owned read carries the verified owner predicate.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { Failure, handleRequest, type Dependencies } from "./handler.ts";

function enabled(): boolean {
  return Deno.env.get("RECIPE_USAGE_ENABLED") !== "false";
}

export function createRecipeUsageDependencies(
  admin: SupabaseClient,
): Dependencies {
  const ownedRead = async (
    table: string,
    columns: string,
    owner: string,
    filters: Record<string, string>,
  ) => {
    let query = admin.from(table).select(columns).eq("owner_id", owner);
    for (const [column, value] of Object.entries(filters)) {
      query = query.eq(column, value);
    }
    const { data, error } = await query.maybeSingle();
    if (error) {
      console.error("recipe_usage_read_failed", { table, code: error.code });
      throw new Failure("SERVICE_UNAVAILABLE");
    }
    return (data as unknown as Record<string, unknown>) ?? null;
  };

  return {
    verifiedOwner: async (request) => {
      const { user } = await requireUser(request);
      return { id: user.id, isAnonymous: user.is_anonymous ?? false };
    },
    isEnabled: enabled,
    loadOwnedJob: (owner, job) =>
      ownedRead("recipe_import_jobs", "id,owner_id,status,result", owner, {
        id: job,
      }),
    loadOwnedSession: (owner, session) =>
      ownedRead("recipe_draft_sessions", "id,owner_id", owner, { id: session }),
    loadOwnedTurn: (owner, session, turn) =>
      ownedRead(
        "recipe_draft_turns",
        "owner_id,session_id,request_id,state,dispatch_state",
        owner,
        { session_id: session, request_id: turn },
      ),
    loadOwnedApproval: (owner, session, turn) =>
      ownedRead(
        "recipe_draft_approvals",
        "owner_id,session_id,turn_request_id,action,receipt",
        owner,
        { session_id: session, turn_request_id: turn },
      ),
    rpc: async (name, args) => {
      const { data, error } = await admin.rpc(name, args);
      if (error) {
        console.error("recipe_usage_rpc_failed", { rpc: name, code: error.code });
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
  return handleRequest(request, createRecipeUsageDependencies(admin));
});
