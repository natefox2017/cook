// Developer: RecipePouch
// Purpose: Authenticated backend capability status without mutable remote imports.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { requireUser } from "../_shared/auth.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  const cors = handleCors(request, "auth");
  if (cors) return cors;
  const headers = authCorsHeaders(request);

  try {
    if (request.method !== "GET") {
      throw new AppError("method_not_allowed", "GET required", 405);
    }

    // Gateway JWT verification is enabled. Independently resolve the user
    // here so a forged or expired token cannot reach the health endpoint.
    await requireUser(request);

    return json(
      {
        ok: true,
        service: "cookapp-backend",
        modules: [
          "auth",
          "user",
          "recipe",
          "collection",
          "ingredient",
          "grocery",
          "meal_plan",
          "pantry",
          "category",
          "storage",
          "subscription",
          "ai_platform",
        ],
        rest_base: "/rest/v1",
        openapi: "/functions/v1/openapi",
      },
      200,
      headers,
    );
  } catch (error) {
    return errorResponse(error, headers);
  }
});
