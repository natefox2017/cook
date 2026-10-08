/** Admin password strength policy (Issue #51). Keep in sync with admin UI copy. */

export const ADMIN_PASSWORD_MIN_LENGTH = 12;

const BLOCKLIST = new Set([
  "admin",
  "password",
  "password123",
  "cookappadmin",
  "adminadmin",
]);

export function validateAdminPassword(password: string): {
  ok: boolean;
  message?: string;
} {
  if (!password || password.length < ADMIN_PASSWORD_MIN_LENGTH) {
    return {
      ok: false,
      message:
        `Password must be at least ${ADMIN_PASSWORD_MIN_LENGTH} characters`,
    };
  }
  if (!/[A-Z]/.test(password)) {
    return { ok: false, message: "Password must include an uppercase letter" };
  }
  if (!/[a-z]/.test(password)) {
    return { ok: false, message: "Password must include a lowercase letter" };
  }
  if (!/[0-9]/.test(password)) {
    return { ok: false, message: "Password must include a digit" };
  }
  if (BLOCKLIST.has(password.toLowerCase())) {
    return { ok: false, message: "Password is too common" };
  }
  return { ok: true };
}

/** True when credentials match the local/dev default seed. */
export function isDefaultAdminCredentials(
  username: string,
  password: string,
): boolean {
  return username.trim().toLowerCase() === "admin" && password === "admin";
}

/**
 * Production blocks default seed login unless ENV is explicitly local/dev.
 * Fail-secure: unset COOKAPP_ADMIN_ENV is treated as production.
 */
export function isAdminProductionRuntime(): boolean {
  const mode = (Deno.env.get("COOKAPP_ADMIN_ENV") ?? "production")
    .toLowerCase();
  return mode !== "development" && mode !== "dev" && mode !== "local";
}

/**
 * Dev-only escape hatch for default admin/admin login.
 * Ignored when runtime is production (even if env var is mistakenly set).
 */
export function allowDefaultAdminCredentials(): boolean {
  if (isAdminProductionRuntime()) return false;
  return (
    (Deno.env.get("COOKAPP_ADMIN_ALLOW_DEFAULT_CREDENTIALS") ?? "")
      .toLowerCase() === "true"
  );
}
