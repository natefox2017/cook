// Account deletion: verifies JWT, purges user storage, deletes auth user via service role.
// Never expose SUPABASE_SERVICE_ROLE_KEY to clients.
// Deploy: supabase functions deploy delete-account --project-ref semsjyrqjnumpvanibip
// Closes: GitHub Issue #11

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { log } from "../_shared/logger.ts";
import { purgeUserStorage } from "../_shared/storage-purge.ts";

const BUCKETS = [
  "avatars",
  "recipe-covers",
  "recipe-images",
  "recipe-import-artifacts",
] as const;
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

    await purgeUserStorage(admin, user.id, BUCKETS);

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
