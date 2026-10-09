// Developer: RecipePouch
// Purpose: Verify dashboard access follows the owner-only financial data contract.

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { AppError } from "../_shared/errors.ts";
import { requireDashboardRole } from "./access.ts";

Deno.test("owner can access the admin dashboard", () => {
  requireDashboardRole("owner");
});

Deno.test("other administrator roles are denied dashboard data", () => {
  for (const role of ["admin", "operator", "readonly"]) {
    try {
      requireDashboardRole(role);
      throw new Error(`${role} was allowed`);
    } catch (error) {
      assertEquals(error instanceof AppError, true);
      assertEquals((error as AppError).status, 403);
      assertEquals((error as AppError).code, "forbidden");
    }
  }
});

Deno.test("unknown dashboard roles fail closed", () => {
  for (const role of [undefined, null, "superuser"]) {
    try {
      requireDashboardRole(role);
      throw new Error("Invalid role was allowed");
    } catch (error) {
      assertEquals(error instanceof AppError, true);
      assertEquals((error as AppError).status, 401);
      assertEquals((error as AppError).code, "unauthorized");
    }
  }
});
