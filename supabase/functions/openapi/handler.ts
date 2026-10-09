// Developer: gengyun
// Purpose: Serve the repository-scoped OpenAPI contract without runtime fetches.

import { handleCors, publicCorsHeaders } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import spec from "./openapi.json" with { type: "json" };

export function handleRequest(request: Request): Response {
  const cors = handleCors(request, "public");
  if (cors) return cors;

  try {
    if (request.method !== "GET") {
      throw new AppError("method_not_allowed", "GET required", 405);
    }

    return json(spec, 200, {
      ...publicCorsHeaders,
      "Cache-Control": "public, max-age=300",
    });
  } catch (error) {
    return errorResponse(error, publicCorsHeaders);
  }
}
