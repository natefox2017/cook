// Developer: RecipePouch
// Purpose: Keep admin privilege checks explicit and fail closed on invalid roles.

import { AppError } from "./errors.ts";

export type AdminRole = "owner" | "admin" | "operator" | "readonly";
const VALID_ADMIN_ROLES = new Set<unknown>(["owner", "admin", "operator", "readonly"]);

export function parseAdminRole(value: unknown): AdminRole {
  if (!VALID_ADMIN_ROLES.has(value)) {
    throw new AppError("unauthorized", "Invalid administrator role", 401);
  }
  return value as AdminRole;
}

/** Every privileged Admin Edge route should declare its authorized role set. */
export function requireAdminRole(
  role: unknown,
  allowed: readonly AdminRole[],
): AdminRole {
  const knownRole = parseAdminRole(role);
  if (!allowed.includes(knownRole)) {
    throw new AppError("forbidden", "This administrator role is not permitted", 403);
  }
  return knownRole;
}
