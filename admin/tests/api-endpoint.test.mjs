import test from "node:test";
import assert from "node:assert/strict";
import { isSecureApiEndpoint } from "../src/api-endpoint.ts";

test("allows same-origin HTTPS proxy and absolute HTTPS functions endpoint", () => {
  assert.equal(isSecureApiEndpoint("/api", "https://admin.shopkivoo.com"), true);
  assert.equal(isSecureApiEndpoint("https://project.supabase.co/functions/v1", "http://localhost:3000"), true);
});

test("rejects insecure, missing and malformed endpoints before sending credentials", () => {
  for (const [base, origin] of [
    ["/api", "http://localhost:3000"],
    ["http://example.com/functions/v1", "https://admin.shopkivoo.com"],
    [undefined, "https://admin.shopkivoo.com"],
    ["https://[", "https://admin.shopkivoo.com"],
  ]) assert.equal(isSecureApiEndpoint(base, origin), false);
});
