/** Shared CORS helpers for CookApp Edge Functions. */

const ALLOW_HEADERS =
  "authorization, x-client-info, apikey, content-type";
const ALLOW_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS";

/** Public endpoints (e.g. openapi) may use a wildcard origin. */
export const publicCorsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": ALLOW_HEADERS,
  "Access-Control-Allow-Methods": ALLOW_METHODS,
};

/**
 * Authenticated browser endpoints: allow only configured origins.
 * Set `CORS_ALLOWED_ORIGINS` to a comma-separated allowlist (e.g. https://app.example.com).
 * Native clients without an Origin header are unaffected.
 */
export function authCorsHeaders(req: Request): Record<string, string> {
  const allowed = (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const origin = req.headers.get("Origin");
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": ALLOW_HEADERS,
    "Access-Control-Allow-Methods": ALLOW_METHODS,
    Vary: "Origin",
  };
  if (origin && allowed.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

/** @deprecated Prefer publicCorsHeaders or authCorsHeaders(req). Kept for call-site clarity. */
export const corsHeaders = publicCorsHeaders;

export function handleCors(
  req: Request,
  mode: "public" | "auth" = "public",
): Response | null {
  if (req.method !== "OPTIONS") return null;
  const headers = mode === "auth" ? authCorsHeaders(req) : publicCorsHeaders;
  return new Response("ok", { headers });
}
