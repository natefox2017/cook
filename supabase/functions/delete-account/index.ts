// Account deletion: verifies JWT, purges user storage, deletes auth user via service role.
// Never expose SUPABASE_SERVICE_ROLE_KEY to clients.
// Deploy: supabase functions deploy delete-account --project-ref semsjyrqjnumpvanibip
// Closes: GitHub Issue #11

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { log } from "../_shared/logger.ts";

const BUCKETS = [
  "avatars",
  "recipe-covers",
  "recipe-images",
  "recipe-import-artifacts",
] as const;
const PAGE = 100;

async function collectPaths(
  admin: ReturnType<typeof createServiceClient>,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];
  for (let offset = 0;; offset += PAGE) {
    const { data: entries, error } = await admin.storage
      .from(bucket)
      .list(prefix, { limit: PAGE, offset });
    if (error) {
      log("error", "storage_list_failed", {
        bucket,
        prefix,
        message: error.message,
      });
      throw new AppError(
        "internal_error",
        "An unexpected error occurred",
        500,
      );
    }
    if (!entries?.length) break;

    for (const entry of entries) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      // Folders have id === null in Supabase Storage list results.
      if (entry.id === null) {
        const nested = await collectPaths(admin, bucket, path);
        paths.push(...nested);
      } else {
        paths.push(path);
      }
    }

    if (entries.length < PAGE) break;
  }
  return paths;
}

async function purgeUserStorage(
  admin: ReturnType<typeof createServiceClient>,
  userId: string,
): Promise<void> {
  for (const bucket of BUCKETS) {
    const paths = await collectPaths(admin, bucket, userId);
    if (!paths.length) continue;

    for (let i = 0; i < paths.length; i += PAGE) {
      const chunk = paths.slice(i, i + PAGE);
      const { error: removeError } = await admin.storage
        .from(bucket)
        .remove(chunk);
      if (removeError) {
        log("error", "storage_remove_failed", {
          bucket,
          message: removeError.message,
          count: chunk.length,
        });
        throw new AppError(
          "internal_error",
          "An unexpected error occurred",
          500,
        );
      }
    }
  }
}

Deno.serve(async (req) => {
  const cors = handleCors(req, "auth");
  if (cors) return cors;
  const headers = authCorsHeaders(req);

  try {
    if (req.method !== "POST") {
      throw new AppError("method_not_allowed", "POST required", 405);
    }

    const { user } = await requireUser(req);
    const admin = createServiceClient();

    log("info", "account_delete_start", { user_id: user.id });

    await purgeUserStorage(admin, user.id);

    // Cascades: profiles, recipes, collections, grocery, meal_plans, pantry, subscriptions
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) {
      log("error", "account_delete_failed", { message: error.message });
      throw new AppError(
        "internal_error",
        "An unexpected error occurred",
        500,
      );
    }

    log("info", "account_delete_ok", { user_id: user.id });
    return json({ ok: true }, 200, headers);
  } catch (err) {
    return errorResponse(err, headers);
  }
});
