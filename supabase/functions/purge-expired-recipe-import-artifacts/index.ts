// Developer: gengyun
// Purpose: Removes expired recipe import objects while retaining minimal metadata.

import { createServiceClient } from "../_shared/auth.ts";

const BUCKET = "recipe-import-artifacts";
const BATCH_SIZE = 100;

Deno.serve(async (request: Request): Promise<Response> => {
  const secret = Deno.env.get("RECIPE_IMPORT_ARTIFACT_CLEANUP_SECRET");
  const authorization = request.headers.get("Authorization");
  if (!secret || authorization !== `Bearer ${secret}`) {
    return Response.json({ code: "AUTH_REQUIRED" }, { status: 401 });
  }
  if (request.method !== "POST") {
    return Response.json({ code: "METHOD_NOT_ALLOWED" }, { status: 405 });
  }

  const admin = createServiceClient();
  const { data: rows, error } = await admin.from("recipe_import_artifacts")
    .select("id,storage_path,state")
    .in("state", ["upload_pending", "available", "rejected"])
    .lte("expires_at", new Date().toISOString())
    .order("expires_at", { ascending: true })
    .limit(BATCH_SIZE);
  if (error) {
    return Response.json({ code: "SERVICE_UNAVAILABLE" }, { status: 503 });
  }

  let deleted = 0;
  for (const row of rows ?? []) {
    const { error: storageError } = await admin.storage.from(BUCKET)
      .remove([row.storage_path]);
    if (storageError) {
      console.error("recipe_import_artifact_cleanup_storage_failed", {
        artifact_id: row.id,
      });
      continue;
    }
    const { error: updateError } = await admin.from("recipe_import_artifacts")
      .update({
        state: "expired",
        updated_at: new Date().toISOString(),
      }).eq("id", row.id).in("state", [
        "upload_pending",
        "available",
        "rejected",
      ]);
    if (updateError) {
      console.error("recipe_import_artifact_cleanup_state_failed", {
        artifact_id: row.id,
      });
      continue;
    }
    deleted++;
  }

  return Response.json({ expired: deleted });
});
