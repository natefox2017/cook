/** Admin dashboard session helpers (custom bearer tokens, not end-user JWT). */

import { createServiceClient } from "./auth.ts";
import { AppError } from "./errors.ts";
import { parseAdminRole, requireAdminRole } from "./admin-role.ts";

const SESSION_TTL_MS = 8 * 60 * 60 * 1000;

export async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function newSessionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function createAdminSession(adminId: string): Promise<{
  token: string;
  expiresAt: string;
}> {
  const admin = createServiceClient();
  const token = newSessionToken();
  const tokenHash = await sha256Hex(token);
  const expiresAt = new Date(Date.now() + SESSION_TTL_MS).toISOString();

  const { error } = await admin.from("admin_sessions").insert({
    admin_id: adminId,
    token_hash: tokenHash,
    expires_at: expiresAt,
  });

  if (error) {
    throw new AppError(
      "internal_error",
      "Failed to create admin session",
      500,
      {
        message: error.message,
      },
    );
  }

  return { token, expiresAt };
}

export async function requireAdminSession(req: Request): Promise<{
  adminId: string;
  username: string;
  role: string;
  sessionId: string;
  token: string;
}> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new AppError(
      "unauthorized",
      "Missing or invalid Authorization header",
      401,
    );
  }
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) {
    throw new AppError("unauthorized", "Missing bearer token", 401);
  }

  const tokenHash = await sha256Hex(token);
  const admin = createServiceClient();
  const { data, error } = await admin
    .from("admin_sessions")
    .select(
      "id, admin_id, expires_at, revoked_at, admin_accounts(username, role)",
    )
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (error) {
    throw new AppError("internal_error", "Session lookup failed", 500, {
      message: error.message,
    });
  }
  if (
    !data || data.revoked_at ||
    new Date(data.expires_at).getTime() <= Date.now()
  ) {
    throw new AppError("unauthorized", "Invalid or expired admin session", 401);
  }

  const account = data.admin_accounts as
    | { username: string; role?: string }
    | { username: string; role?: string }[]
    | null;
  const row = Array.isArray(account) ? account[0] : account;
  const username = row?.username;
  if (!username) {
    throw new AppError("unauthorized", "Invalid admin session", 401);
  }

  return {
    adminId: data.admin_id as string,
    username,
    // Never promote a missing/corrupt role into an owner-level session.
    role: parseAdminRole(row?.role),
    sessionId: data.id as string,
    token,
  };
}

/** Owner-only gate for secrets / financial / admin-account APIs. */
export function requireOwnerRole(role: string): void {
  requireAdminRole(role, ["owner"]);
}
