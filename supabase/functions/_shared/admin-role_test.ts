// Developer: RecipePouch
// Purpose: Prevent missing or read-only admin roles from inheriting owner privileges.

import { AppError } from "./errors.ts";
import { parseAdminRole, requireAdminRole } from "./admin-role.ts";

function assert(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}

function expectDenied(
  operation: () => unknown,
  status: number,
): void {
  try {
    operation();
  } catch (error) {
    assert(error instanceof AppError, "Expected an authorization failure");
    assert(error.status === status, `Unexpected authorization status ${error.status}`);
    return;
  }
  throw new Error("Unprivileged admin role was accepted");
}

Deno.test("all four database-backed admin roles parse exactly", () => {
  for (const role of ["owner", "admin", "operator", "readonly"]) {
    assert(parseAdminRole(role) === role, `Valid role ${role} was rejected`);
  }
});

Deno.test("unknown and missing roles fail closed instead of becoming owner", () => {
  for (const role of [null, undefined, "", "OWNER", "superuser", [], {}]) {
    expectDenied(() => parseAdminRole(role), 401);
  }
});

Deno.test("owner authorization never accepts admin, operator or readonly", () => {
  assert(requireAdminRole("owner", ["owner"]) === "owner", "Owner was rejected");
  for (const role of ["admin", "operator", "readonly"]) {
    expectDenied(() => requireAdminRole(role, ["owner"]), 403);
  }
});

Deno.test("readonly cannot mutate subscription or financial routes", () => {
  expectDenied(() => requireAdminRole("readonly", ["owner", "admin"]), 403);
  expectDenied(() => requireAdminRole("operator", ["owner", "admin"]), 403);
  assert(requireAdminRole("readonly", ["owner", "admin", "operator", "readonly"]) ===
    "readonly", "A read-only status endpoint must remain accessible");
});

Deno.test("authorization handles malformed role before checking allowed roles", () => {
  expectDenied(() => requireAdminRole(undefined, ["owner"]), 401);
  expectDenied(() => requireAdminRole("superuser", ["owner"]), 401);
});
