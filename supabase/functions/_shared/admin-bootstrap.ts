import { AppError } from "./errors.ts";

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

  if (!presented || presented !== expectedToken) {
    throw new AppError(
      "forbidden",
      "Invalid or missing bootstrap token",
      403,
    );
  }

  return handleAuthorizedRequest();
}
