// Developer: gengyun
// Purpose: Verify strict request field and input exclusivity matches Import V1.

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { hasImportRequestShape } from "./requestValidation.ts";

Deno.test("accepts a URL request with frozen optional metadata", () => {
  assertEquals(
    hasImportRequestShape({
      client_request_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      input_type: "url",
      url: "https://recipes.example/soup",
      original_source_url: "https://social.example/post/1",
      platform_hint: "social",
    }),
    true,
  );
});

Deno.test("rejects mixed inputs, unknown fields and invalid artifact IDs", () => {
  assertEquals(
    hasImportRequestShape({
      input_type: "url",
      url: "https://recipes.example/soup",
      text: "extra source",
    }),
    false,
  );
  assertEquals(
    hasImportRequestShape({ input_type: "text", text: "Soup", extra: true }),
    false,
  );
  assertEquals(
    hasImportRequestShape({ input_type: "image", artifact_id: "not-a-uuid" }),
    false,
  );
});
