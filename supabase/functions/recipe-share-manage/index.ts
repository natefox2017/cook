// Developer: Recipe Pals
// Purpose: Authenticated, owner-only public-recipe publication. The service key never leaves Edge.

import {createServiceClient, requireUser} from "../_shared/auth.ts";
import {
  boundedJSON,
  contentDigest,
  httpError,
  isUUID,
  managePayload,
  privacyHeaders,
  randomSlug,
  routeTail,
  versionMatch,
  webOrigin,
} from "../_shared/recipeShareContract.mjs";

const TABLE = "recipe_shared_snapshots";
const RETURNING = "share_id,owner_id,source_recipe_id,opaque_slug,share_version,scope,created_at,updated_at,revoked_at";
const MAX_DAILY_CREATES = 200;

interface ShareRow {
  share_id: string;
  owner_id: string;
  source_recipe_id: string;
  opaque_slug: string;
  share_version: number;
  scope: string;
  created_at: string;
  updated_at: string;
  revoked_at: string | null;
  request_hash?: string;
}

function metadata(row: ShareRow, origin: string): Record<string, unknown> {
  return {
    shareID: row.share_id,
    sourceRecipeID: row.source_recipe_id,
    slug: row.opaque_slug,
    shareVersion: row.share_version,
    scope: row.scope,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    revokedAt: row.revoked_at,
    publicURL: origin + "/r/" + row.opaque_slug,
  };
}

function noContent(): Response {
  return new Response(null, {status: 204, headers: privacyHeaders()});
}

function failDatabase(error: {code?: string} | null, context: string): Response {
  // Do not log SQL text, user IDs, input JSON or credentials.
  console.error("recipe_share_" + context, {code: error?.code ?? "unknown"});
  return httpError("service_unavailable", 503);
}

export async function handleRecipeShareManage(request: Request): Promise<Response> {
  const isPost = request.method === "POST";
  const isGet = request.method === "GET";
  const isPut = request.method === "PUT";
  const isDelete = request.method === "DELETE";
  if (!isPost && !isGet && !isPut && !isDelete) {
    return httpError("method_not_allowed", 405);
  }

  // No platform API-key or service-role key is accepted as a user identity.
  let userID: string;
  try {
    const {user} = await requireUser(request);
    if (user.is_anonymous) return httpError("unauthorized", 401);
    userID = user.id;
  } catch {
    return httpError("unauthorized", 401);
  }

  let tail: string[] | null;
  try {
    tail = routeTail(request.url, "recipe-share-manage");
  } catch {
    return httpError("not_found", 404);
  }
  if (!tail || tail.length > 1 || (tail.length === 1 && !isUUID(tail[0]))) {
    return httpError("not_found", 404);
  }
  if ((isPost && tail.length !== 0) || ((isPut || isDelete) && tail.length !== 1)) {
    return httpError("method_not_allowed", 405);
  }

  // Real host must be configured by the authorized staging/deployment owner.
  // An example/default domain must never produce a public URL.
  const origin = webOrigin(Deno.env.get("RECIPE_PALS_PUBLIC_WEB_ORIGIN"));
  if (!origin) return httpError("service_unavailable", 503);

  let admin: ReturnType<typeof createServiceClient>;
  try {
    admin = createServiceClient();
  } catch {
    return httpError("service_unavailable", 503);
  }

  if (isGet) {
    const query = admin.from(TABLE).select(RETURNING).eq("owner_id", userID);
    if (tail.length === 0) {
      const {data, error} = await query.order("created_at", {ascending: false}).limit(200);
      if (error) return failDatabase(error, "owner_list_failed");
      return Response.json({shares: (data as ShareRow[]).map((row) => metadata(row, origin))}, {
        headers: privacyHeaders(),
      });
    }
    const {data, error} = await query.eq("share_id", tail[0]).maybeSingle();
    if (error) return failDatabase(error, "owner_read_failed");
    if (!data) return httpError("not_found", 404);
    return Response.json(metadata(data as ShareRow, origin), {headers: privacyHeaders()});
  }

  if (isPost || isPut) {
    const parsed = await boundedJSON(request);
    if ("error" in parsed) {
      return httpError(parsed.error === 413 ? "payload_too_large" : "invalid_input", parsed.error);
    }
    const payload = managePayload(parsed.value, isPost);
    if (!payload) return httpError("invalid_input", 400);
    const content = payload.snapshot;

    if (isPost) {
      const requestHash = await contentDigest(payload);
      // A retry of an existing request must not consume the daily creation budget.
      const {data: previous, error: priorError} = await admin.from(TABLE)
        .select(RETURNING + ",request_hash")
        .eq("owner_id", userID).eq("idempotency_key", payload.idempotencyKey)
        .maybeSingle();
      if (priorError) return failDatabase(priorError, "request_lookup_failed");
      if (previous) {
        if (previous.request_hash !== requestHash || previous.revoked_at) {
          return httpError("idempotency_conflict", 409);
        }
        return Response.json(metadata(previous as ShareRow, origin), {
          status: 200, headers: privacyHeaders(),
        });
      }

      const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
      const {count, error: countError} = await admin.from(TABLE)
        .select("share_id", {head: true, count: "exact"})
        .eq("owner_id", userID).gte("created_at", since);
      if (countError) return failDatabase(countError, "quota_failed");
      if ((count ?? 0) >= MAX_DAILY_CREATES) return httpError("rate_limited", 429);

      const {data, error} = await admin.from(TABLE).insert({
        owner_id: userID,
        source_recipe_id: payload.sourceRecipeID,
        source_client_updated_at: payload.sourceRecipeUpdatedAt,
        opaque_slug: randomSlug(),
        share_version: 1,
        scope: payload.scope,
        has_distribution_rights: payload.hasDistributionRights,
        sanitized_snapshot: content,
        idempotency_key: payload.idempotencyKey,
        request_hash: requestHash,
      }).select(RETURNING).single();
      if (error?.code === "23505") {
        // Concurrent identical POST: unique (owner_id,idempotency_key) wins.
        const {data: winner, error: winnerError} = await admin.from(TABLE)
          .select(RETURNING + ",request_hash")
          .eq("owner_id", userID).eq("idempotency_key", payload.idempotencyKey)
          .maybeSingle();
        if (winnerError) return failDatabase(winnerError, "duplicate_lookup_failed");
        if (winner && !winner.revoked_at && winner.request_hash === requestHash) {
          return Response.json(metadata(winner as ShareRow, origin), {
            status: 200, headers: privacyHeaders(),
          });
        }
        return httpError("idempotency_conflict", 409);
      }
      if (error || !data) return failDatabase(error, "create_failed");
      return Response.json(metadata(data as ShareRow, origin), {
        status: 201, headers: privacyHeaders(),
      });
    }

    const expected = versionMatch(request.headers.get("if-match"));
    if (expected === null) return httpError("revision_conflict", 409);
    const {data, error} = await admin.from(TABLE)
      .update({
        source_recipe_id: payload.sourceRecipeID,
        source_client_updated_at: payload.sourceRecipeUpdatedAt,
        scope: payload.scope,
        has_distribution_rights: payload.hasDistributionRights,
        sanitized_snapshot: content,
        share_version: expected + 1,
        updated_at: new Date().toISOString(),
      })
      .eq("owner_id", userID).eq("share_id", tail[0])
      .eq("share_version", expected).is("revoked_at", null)
      .select(RETURNING).maybeSingle();
    if (error) return failDatabase(error, "update_failed");
    if (data) return Response.json(metadata(data as ShareRow, origin), {
      status: 200, headers: privacyHeaders(),
    });
    const {data: existing, error: existingError} = await admin.from(TABLE)
      .select("share_id,revoked_at").eq("owner_id", userID)
      .eq("share_id", tail[0]).maybeSingle();
    if (existingError) return failDatabase(existingError, "update_lookup_failed");
    return httpError(!existing || existing.revoked_at ? "not_found" : "revision_conflict",
      !existing || existing.revoked_at ? 404 : 409);
  }

  // DELETE takes precedence over concurrent updates. It never un-revokes.
  const {data: prior, error: readError} = await admin.from(TABLE)
    .select("share_id,revoked_at").eq("owner_id", userID)
    .eq("share_id", tail[0]).maybeSingle();
  if (readError) return failDatabase(readError, "revoke_lookup_failed");
  if (!prior) return httpError("not_found", 404);
  if (prior.revoked_at) return noContent();

  const {data: deleted, error: deleteError} = await admin.from(TABLE).update({
    revoked_at: new Date().toISOString(),
    sanitized_snapshot: null,
    updated_at: new Date().toISOString(),
  }).eq("owner_id", userID).eq("share_id", tail[0])
    .is("revoked_at", null).select("share_id").maybeSingle();
  if (deleteError) return failDatabase(deleteError, "revoke_failed");
  if (deleted) return noContent();

  // Another delete may have won the race; still idempotently return 204.
  const {data: latest, error: latestError} = await admin.from(TABLE)
    .select("revoked_at").eq("owner_id", userID)
    .eq("share_id", tail[0]).maybeSingle();
  if (latestError) return failDatabase(latestError, "revoke_confirm_failed");
  return latest?.revoked_at ? noContent() : httpError("service_unavailable", 503);
}

Deno.serve(handleRecipeShareManage);
