// Developer: gengyun
// Purpose: Verify v2 encryption integrity and explicit rejection of opaque legacy keys.
import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import { encryptAISecret, resolveAISecret } from "../_shared/ai-secret.ts";
import { AppError } from "../_shared/errors.ts";
const key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
Deno.test("v2 roundtrip uses fresh references and nonces", async () => {
  const first = await encryptAISecret("synthetic-secret", key);
  const second = await encryptAISecret("synthetic-secret", key);
  assertEquals(first.key_version, 2);
  assertEquals(first.nonce.length, 16);
  assertNotEquals(first.secret_ref, second.secret_ref);
  assertNotEquals(first.nonce, second.nonce);
  assertEquals(await resolveAISecret(first, key), "synthetic-secret");
  assertEquals(first.ciphertext.includes("synthetic-secret"), false);
});
Deno.test("v2 binds the reference and rejects cipher, nonce, and key tampering", async () => {
  const secret = await encryptAISecret("synthetic-secret", key);
  for (
    const changed of [
      { ...secret, secret_ref: crypto.randomUUID() },
      {
        ...secret,
        ciphertext: (secret.ciphertext[0] === "A" ? "B" : "A") +
          secret.ciphertext.slice(1),
      },
      { ...secret, nonce: "AAAAAAAAAAAAAAAB" },
    ]
  ) {
    await assertRejects(() => resolveAISecret(changed, key), AppError);
  }
  await assertRejects(
    () =>
      resolveAISecret(secret, "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"),
    AppError,
  );
});
Deno.test("opaque v1 and unknown versions are rejected without a key", async () => {
  for (const version of [1, 3]) {
    const secret = {
      secret_ref: "opaque",
      ciphertext: "unchanged",
      nonce: "unchanged",
      key_version: version,
    };
    const error = await assertRejects(
      () => resolveAISecret(secret, ""),
      AppError,
    );
    assertEquals(error.status, 409);
    assertEquals(secret.ciphertext, "unchanged");
  }
});
Deno.test("invalid configured keys fail closed", async () => {
  for (const invalid of ["", "short", key + "=", "a".repeat(43)]) {
    await assertRejects(() => encryptAISecret("synthetic", invalid), AppError);
  }
});
