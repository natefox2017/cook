/** Structured JSON responses + AppError helpers. */

import { publicCorsHeaders } from "./cors.ts";

export type ErrorCode =
  | "unauthorized"
  | "forbidden"
  | "not_found"
  | "validation_error"
  | "method_not_allowed"
  | "conflict"
  | "server_misconfigured"
  | "internal_error";

export class AppError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
    public readonly status = 400,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "AppError";
  }
}

export function json(
  body: unknown,
  status = 200,
  cors: Record<string, string> = publicCorsHeaders,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
    },
  });
}

export function errorResponse(
  err: unknown,
  cors: Record<string, string> = publicCorsHeaders,
): Response {
  if (err instanceof AppError) {
    return json(
      {
        error: {
          code: err.code,
          message: err.message,
          details: err.details ?? null,
        },
      },
      err.status,
      cors,
    );
  }
  const message = err instanceof Error ? err.message : "unknown_error";
  console.error("unhandled_error", message);
  return json(
    {
      error: {
        code: "internal_error",
        message: "An unexpected error occurred",
        details: null,
      },
    },
    500,
    cors,
  );
}
