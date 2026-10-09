// Developer: gengyun
// Purpose: Verify RevenueCat webhook authentication and payload normalization.

import {
  msToIso,
  sanitize,
  STATUS_MAP,
  timingSafeEqual,
  UUID_RE,
  verifySignature,
} from "./webhook.ts";

Deno.test("webhook bearer comparison accepts equal values and rejects mismatches", async () => {
  if (!await timingSafeEqual("Bearer secret", "Bearer secret")) {
    throw new Error("equal bearer values must match");
  }
  if (await timingSafeEqual("Bearer secret", "Bearer other")) {
    throw new Error("different bearer values must not match");
  }
});

Deno.test("provider signatures authenticate exact bytes and expire independently of event time", async () => {
  const body = new TextEncoder().encode('{ "event": {} }');
  const secret = "local-signing-fixture";
  const timestamp = "1700000000";
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(timestamp + '.{ "event": {} }'),
    ),
  );
  const signature = Array.from(
    digest,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  const header = `t=${timestamp},v1=${signature}`;
  if (!await verifySignature(body, header, secret, 1700000000000)) {
    throw new Error("valid signature rejected");
  }
  if (
    await verifySignature(
      new TextEncoder().encode('{"event":{}}'),
      header,
      secret,
      1700000000000,
    )
  ) throw new Error("modified bytes accepted");
  if (await verifySignature(body, header, secret, 1700000301000)) {
    throw new Error("stale signature accepted");
  }
  if (await verifySignature(body, header, "wrong-secret", 1700000000000)) {
    throw new Error("wrong signing secret accepted");
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
