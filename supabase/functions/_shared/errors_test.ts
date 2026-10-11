// Developer: RecipePouch
// Purpose: Prevent internal database and service failure details leaking in API responses.

import { AppError, errorResponse } from "./errors.ts";

Deno.test("HTTP 5xx replies never expose database internals", async () => {
  const response = errorResponse(
    new AppError(
      "internal_error",
      "Session lookup failed: relation public.admin_sessions is missing",
      500,
      { message: "relation public.admin_sessions not found", sql: "select * ..." },
    ),
  );
  const result = await response.json();
  if (response.status !== 500 || result.error?.details !== null) {
    throw new Error("Database error details leaked to the HTTP client.");
  }
  if (JSON.stringify(result).includes("admin_sessions")) {
    throw new Error("Server schema details leaked to the HTTP client.");
  }
});

Deno.test("Validation errors can retain public client-actionable details", async () => {
  const response = errorResponse(
    new AppError("validation_error", "Invalid source", 400, {
      field: "source_url",
    }),
  );
  const result = await response.json();
  if (response.status !== 400 || result.error?.details?.field !== "source_url") {
    throw new Error("Safe client validation details were lost.");
  }
});

Deno.test("Unhandled exceptions never expose raw error messages in responses or logs", async () => {
  const previous = console.error;
  const logs: unknown[][] = [];
  console.error = (...args: unknown[]) => { logs.push(args); };
  try {
    const response = errorResponse(new Error("SUPABASE_SERVICE_ROLE_KEY=fixture-secret"));
    const result = await response.json();
    if (response.status !== 500 || JSON.stringify([result, logs]).includes("fixture-secret")) {
      throw new Error("Unhandled exception text escaped to a caller or log.");
    }
    if (logs.length !== 1 || logs[0][0] !== "unhandled_error") {
      throw new Error("The fixed diagnostic event was lost.");
    }
  } finally {
    console.error = previous;
  }
});
