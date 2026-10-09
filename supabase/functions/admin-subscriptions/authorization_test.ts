import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { authorizeSubscriptionRoute } from "./authorization.ts";

Deno.test("owner and admin can write subscription plans", () => {
  for (const role of ["owner", "admin"]) {
    for (const method of ["POST", "PUT", "DELETE"]) {
      authorizeSubscriptionRoute(role, "plans", method);
    }
  }
});

Deno.test("operator and readonly cannot write subscription plans", () => {
  for (const role of ["operator", "readonly"]) {
    for (const method of ["POST", "PUT", "DELETE"]) {
      assertThrows(
        () => authorizeSubscriptionRoute(role, "plans", method),
        Error,
        "This administrator role is not permitted",
      );
    }
  }
});

Deno.test("only owner and admin can read subscription records and revenue", () => {
  for (const role of ["owner", "admin"]) {
    authorizeSubscriptionRoute(role, "records", "GET");
    authorizeSubscriptionRoute(role, "revenue", "GET");
  }

  for (const role of ["operator", "readonly"]) {
    assertThrows(
      () => authorizeSubscriptionRoute(role, "records", "GET"),
      Error,
      "This administrator role is not permitted",
    );
    assertThrows(
      () => authorizeSubscriptionRoute(role, "revenue", "GET"),
      Error,
      "This administrator role is not permitted",
    );
  }
});

Deno.test("plan catalog reads preserve session-only access", () => {
  for (const role of ["owner", "admin", "operator", "readonly"]) {
    assertEquals(
      authorizeSubscriptionRoute(role, "plans", "GET"),
      undefined,
    );
  }
});
