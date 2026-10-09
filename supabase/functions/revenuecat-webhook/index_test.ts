// Developer: RecipePouch
// Purpose: Verify RevenueCat webhook authentication and payload normalization.

import {
  msToIso,
  sanitize,
  STATUS_MAP,
  timingSafeEqual,
  UUID_RE,
} from "./webhook.ts";

Deno.test("webhook bearer comparison accepts equal values and rejects mismatches", async () => {
  if (!await timingSafeEqual("Bearer secret", "Bearer secret")) {
    throw new Error("equal bearer values must match");
  }
  if (await timingSafeEqual("Bearer secret", "Bearer other")) {
    throw new Error("different bearer values must not match");
  }
});

Deno.test("event mappings and user IDs preserve the webhook contract", () => {
  if (STATUS_MAP.INITIAL_PURCHASE !== "active") {
    throw new Error("initial purchases must activate a subscription");
  }
  if (STATUS_MAP.EXPIRATION !== "expired") {
    throw new Error("expiration events must expire a subscription");
  }
  if (!UUID_RE.test("123e4567-e89b-42d3-a456-426614174000")) {
    throw new Error("valid UUID was rejected");
  }
  if (UUID_RE.test("not-a-user-id")) {
    throw new Error("invalid user ID was accepted");
  }
});

Deno.test("timestamp parsing and raw event sanitization", () => {
  if (msToIso("1700000000000") !== "2023-11-14T22:13:20.000Z") {
    throw new Error("millisecond timestamp was not normalized");
  }
  if (msToIso("not-a-timestamp") !== null || msToIso(0) !== null) {
    throw new Error("invalid or empty timestamps must be omitted");
  }

  const safe = sanitize({
    type: "INITIAL_PURCHASE",
    product_id: "monthly",
    app_user_id: "private-user-reference",
    customer_email: "private@example.com",
  }, "event-123");
  if (safe.type !== "INITIAL_PURCHASE" || safe.rc_event_id !== "event-123") {
    throw new Error("allowed event fields were not preserved");
  }
  if ("app_user_id" in safe || "customer_email" in safe) {
    throw new Error("private customer fields must be omitted");
  }
});
