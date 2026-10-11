import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { requirePassword } from "./input.ts";
import { AppError } from "../_shared/errors.ts";
Deno.test("password inputs preserve whitespace and reject coercion", () => {
  assertEquals(
    requirePassword({ password: " leading and trailing " }, "password"),
    " leading and trailing ",
  );
  for (
    const password of [
      undefined,
      null,
      123,
      false,
      {},
      [],
      "",
      "x".repeat(4097),
    ]
  ) assertThrows(() => requirePassword({ password }, "password"), AppError);
});
