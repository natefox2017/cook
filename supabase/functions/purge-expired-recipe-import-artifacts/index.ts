// Developer: RecipePouch
// Purpose: Private scheduled cleanup of expired recipe import attachments.

import { createServiceClient } from "../_shared/auth.ts";
import {
  purgeExpiredArtifacts,
  securelyEqual,
  type ArtifactPurgeSource,
  type ExpiredArtifact,
} from "./purge.ts";

const BUCKET = "recipe-import-artifacts";
const EXPIRABLE_STATES = ["upload_pending", "available", "rejected"];

Deno.serve(async (request: Request): Promise<Response> => {
  // verify_jwt=false is intentional for scheduler requests; only a separate
  // high-entropy server secret authorizes service-role cleanup.
  const secret = Deno.env.get("RECIPE_IMPORT_ARTIFACT_CLEANUP_SECRET");
  if (!secret || !securelyEqual(
    request.headers.get("Authorization") ?? "",
    `Bearer ${secret}`,
  )) {
    return Response.json({ code: "AUTH_REQUIRED" }, { status: 401 });
  }
  if (request.method !== "POST") {
    return Response.json({ code: "METHOD_NOT_ALLOWED" }, { status: 405 });
  }

  try {
    const admin = createServiceClient();
    const source: ArtifactPurgeSource = {
      listExpired: async (cutoff, offset, limit) => {
        const { data, error } = await admin.from("recipe_import_artifacts")
          .select("id,owner_id,storage_bucket,storage_path,state,expires_at")
          .in("state", EXPIRABLE_STATES)
          .lte("expires_at", cutoff)
          .order("expires_at", { ascending: true })
          .order("id", { ascending: true })
          .range(offset, offset + limit - 1);
        if (error) throw new Error("Artifact cleanup read failed");
        return (data ?? []) as ExpiredArtifact[];
      },
      remove: async (path) => {
        const { error } = await admin.storage.from(BUCKET).remove([path]);
        if (error) throw new Error("Artifact cleanup Storage removal failed");
      },
      markExpired: async (row, cutoff) => {
        const { data, error } = await admin.from("recipe_import_artifacts")
          .update({ state: "expired", updated_at: new Date().toISOString() })
          .eq("id", row.id)
          .eq("owner_id", row.owner_id)
          .eq("storage_bucket", BUCKET)
          .eq("storage_path", row.storage_path)
          .eq("expires_at", row.expires_at)
          .lte("expires_at", cutoff)
          .in("state", EXPIRABLE_STATES)
          .select("id")
          .maybeSingle();
        if (error) throw new Error("Artifact cleanup state update failed");
        return data !== null;
      },
    };

    const report = await purgeExpiredArtifacts(source);
    if (report.failed > 0 || report.has_more) {
      // No user identifiers, source text, tokens or object paths in logs.
      console.warn("recipe_artifact_cleanup_incomplete", report);
    }
    // Partial failure is explicitly retryable for the scheduler and alarm.
    return Response.json(report, { status: report.failed > 0 ? 503 : 200 });
  } catch {
    console.error("recipe_artifact_cleanup_unavailable");
    return Response.json({ code: "SERVICE_UNAVAILABLE" }, { status: 503 });
  }
});
