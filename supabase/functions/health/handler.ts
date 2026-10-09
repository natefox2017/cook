import { requireUser } from "../_shared/auth.ts";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";

export type HealthAuthenticator = (request: Request) => Promise<unknown>;

/** Builds the authenticated health handler; the injectable auth boundary supports local HTTP checks. */
export function createHealthHandler(
  authenticate: HealthAuthenticator = requireUser,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    const cors = handleCors(request, "auth");
    if (cors) return cors;
    const headers = authCorsHeaders(request);

    try {
      if (request.method !== "GET") {
        throw new AppError("method_not_allowed", "GET required", 405);
      }

      // Gateway JWT verification is enabled. Independently resolve the user
      // here so a forged or expired token cannot reach the health endpoint.
      await authenticate(request);

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
  };
}
