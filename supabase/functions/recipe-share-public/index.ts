// Developer: Recipe Pals
// Purpose: Anonymous, non-enumerable, eight-field snapshot read. Never query private Recipe data.

import {createServiceClient} from "../_shared/auth.ts";
import {
  httpError, privacyHeaders, publicSnapshot, routeTail,
} from "../_shared/recipeShareContract.mjs";

const SLUG = /^[A-Za-z0-9_-]{8,128}$/;

export async function handlePublicShare(request: Request): Promise<Response> {
  const headers = privacyHeaders();
  if (request.method !== "GET" && request.method !== "HEAD") {
    return httpError("method_not_allowed", 405);
  }

  let tail: string[] | null;
  try {
    tail = routeTail(request.url, "recipe-share-public");
  } catch {
    return httpError("not_found", 404);
  }
  if (!tail || tail.length !== 1 || !SLUG.test(tail[0])) {
    return httpError("not_found", 404);
  }

  try {
    // Only a server-side service credential can select a share. RLS rejects
    // public direct-table access, and this handler never forwards database rows.
    const admin = createServiceClient();
    const {data, error} = await admin.from("recipe_shared_snapshots")
      .select("sanitized_snapshot,scope,has_distribution_rights")
      .eq("opaque_slug", tail[0])
      .is("revoked_at", null)
      .maybeSingle();

    if (error) {
      console.error("recipe_share_public_read_failed", {code: error.code});
      return httpError("service_unavailable", 503);
    }
    if (!data || !data.sanitized_snapshot) return httpError("not_found", 404);
    const snapshot = publicSnapshot(data.sanitized_snapshot);
    if (!snapshot ||
      (data.scope === "summaryAndSource" &&
        (snapshot.ingredients.length > 0 || snapshot.steps.length > 0)) ||
      (data.scope === "fullInstructions" && data.has_distribution_rights !== true) ||
      !["summaryAndSource", "fullInstructions"].includes(data.scope)) {
      console.error("recipe_share_public_invalid_stored_snapshot");
      return httpError("service_unavailable", 503);
    }

    if (request.method === "HEAD") {
      return new Response(null, {status: 200, headers: {
        ...headers, "Content-Type": "application/json; charset=utf-8",
      }});
    }
    return Response.json(snapshot, {status: 200, headers});
  } catch {
    return httpError("service_unavailable", 503);
  }
}

Deno.serve(handlePublicShare);
