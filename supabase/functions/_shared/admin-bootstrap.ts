import { AppError } from "./errors.ts";
import { securelyEqualTokens } from "./secure-token.ts";

export async function withAdminBootstrapAuthorization<T>(
  req: Request,
  expectedToken: string,
  isProduction: boolean,
  handleAuthorizedRequest: () => Promise<T>,
): Promise<T> {
  if (isProduction && !expectedToken) {
    throw new AppError(
      "server_misconfigured",
      "COOKAPP_ADMIN_BOOTSTRAP_TOKEN is required before production bootstrap",
      500,
    );
  }

  if (!isProduction && !expectedToken) {
    return handleAuthorizedRequest();
  }

  const header = req.headers.get("X-CookApp-Bootstrap-Token")?.trim() ?? "";
  const authorization = req.headers.get("Authorization") ?? "";
  const bearer = authorization.startsWith("Bearer ")
    ? authorization.slice(7).trim()
    : "";
  const presented = header || bearer;

  if (!presented || !securelyEqualTokens(presented, expectedToken)) {
    throw new AppError(
      "forbidden",
      "Invalid or missing bootstrap token",
      403,
    );
  }

  return handleAuthorizedRequest();
}

/**
 * Preserve actionable bootstrap errors without exposing internal Postgres or
 * privileged RPC diagnostics to an unauthenticated bootstrap caller.
 */
export function publicAdminBootstrapError(message: string): AppError {
  if (message.includes("current default password")) {
    return new AppError(
      "unauthorized",
      "Current default password is incorrect",
      401,
    );
  }
  if (message.includes("strength")) {
    return new AppError(
      "validation_error",
      "newPassword does not meet strength policy",
      400,
    );
  }
  if (message.includes("not available")) {
    return new AppError(
      "conflict",
      "Bootstrap is not available for this environment",
      409,
    );
  }
  return new AppError("internal_error", "Bootstrap failed", 500);
}
