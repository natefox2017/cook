/** Authenticated Supabase clients for Edge Functions. */

import { createClient, type SupabaseClient, type User } from
  "jsr:@supabase/supabase-js@2";
import { AppError } from "./errors.ts";

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new AppError(
      "server_misconfigured",
      `Missing environment variable: ${name}`,
      500,
    );
  }
  return value;
}

export function createUserClient(authHeader: string): SupabaseClient {
  const url = requireEnv("SUPABASE_URL");
  const anon = requireEnv("SUPABASE_ANON_KEY");
  return createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export function createServiceClient(): SupabaseClient {
  const url = requireEnv("SUPABASE_URL");
  const serviceRole = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  return createClient(url, serviceRole, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function requireUser(req: Request): Promise<{
  user: User;
  userClient: SupabaseClient;
  authHeader: string;
}> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new AppError("unauthorized", "Missing or invalid Authorization header", 401);
  }
  const userClient = createUserClient(authHeader);
  const {
    data: { user },
    error,
  } = await userClient.auth.getUser();
  if (error || !user) {
    throw new AppError("unauthorized", "Invalid or expired session", 401);
  }
  return { user, userClient, authHeader };
}
