import { AppError } from "../_shared/errors.ts";

// Password bytes are significant: validate types without trimming or coercion.
export function requirePassword(
  body: Record<string, unknown>,
  key: string,
): string {
  const value = body[key];
  if (typeof value !== "string" || !value || value.length > 4096) {
    throw new AppError(
      "validation_error",
      `${key} must be a nonempty password string`,
      400,
    );
  }
  return value;
}
