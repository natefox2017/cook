// Developer: gengyun
// Purpose: Verify TOTP, replay checks, encrypted persistence, and challenge primitives locally.

import {
  decryptTotpSecret,
  encryptTotpSecret,
  hashChallenge,
  matchingTotpCounter,
  newChallenge,
  newTotpSecret,
  totpAt,
  webauthnConfig,
} from "./factors.ts";

Deno.test("TOTP follows RFC 6238 SHA-1 vectors and rejects replayed counters", async () => {
  const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
  const code = await totpAt(secret, 59_000);
  if (code !== "287082") throw new Error(`Unexpected RFC 6238 code: ${code}`);
  if (await matchingTotpCounter(secret, code, 59_000, 1) !== null) {
    throw new Error("A previously accepted TOTP counter was allowed again.");
  }
  if (await matchingTotpCounter(secret, code, 59_000, 0) !== 1) {
    throw new Error("The current valid TOTP counter was rejected.");
  }
  if (await matchingTotpCounter(secret, "12345", 59_000) !== null) {
    throw new Error("A malformed TOTP code was accepted.");
  }
});

Deno.test("TOTP encryption authenticates ciphertext and requires a 256-bit key", async () => {
  const key = "A".repeat(43);
  const secret = newTotpSecret();
  if (secret.length !== 32) throw new Error("Unexpected secret length.");
  const ciphertext = await encryptTotpSecret(secret, key);
  if (ciphertext.includes(secret)) {
    throw new Error("The stored TOTP value contains the plaintext secret.");
  }
  if (await decryptTotpSecret(ciphertext, key) !== secret) {
    throw new Error("Encrypted secret did not round-trip.");
  }
  let rejected = false;
  try {
    await decryptTotpSecret(ciphertext, "B".repeat(43));
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Ciphertext decrypted under a different key.");
});

Deno.test("factor challenges are random and stored through a one-way digest", async () => {
  const first = newChallenge();
  const second = newChallenge();
  if (first === second) {
    throw new Error("Challenge generation repeated a value.");
  }
  if (await hashChallenge(first) === first) {
    throw new Error("Challenge digest did not transform the token.");
  }
});

Deno.test("WebAuthn configuration requires a secure origin within its RP ID", () => {
  const originalOrigin = Deno.env.get("ADMIN_WEBAUTHN_ORIGIN");
  const originalRPID = Deno.env.get("ADMIN_WEBAUTHN_RP_ID");
  try {
    Deno.env.set("ADMIN_WEBAUTHN_ORIGIN", "https://admin.example.com");
    Deno.env.set("ADMIN_WEBAUTHN_RP_ID", "example.com");
    const config = webauthnConfig();
    if (
      config.origin !== "https://admin.example.com" ||
      config.rpID !== "example.com"
    ) {
      throw new Error("Valid WebAuthn configuration was changed.");
    }

    for (
      const [origin, rpID] of [
        ["http://admin.example.com", "example.com"],
        ["https://example.com.attacker.test", "example.com"],
        ["https://admin.example.com", "other.test"],
        ["https://admin.example.com/", "example.com"],
      ]
    ) {
      Deno.env.set("ADMIN_WEBAUTHN_ORIGIN", origin);
      Deno.env.set("ADMIN_WEBAUTHN_RP_ID", rpID);
      let rejected = false;
      try {
        webauthnConfig();
      } catch {
        rejected = true;
      }
      if (!rejected) {
        throw new Error(
          `Unsafe WebAuthn configuration was accepted: ${origin} / ${rpID}`,
        );
      }
    }
  } finally {
    if (originalOrigin === undefined) Deno.env.delete("ADMIN_WEBAUTHN_ORIGIN");
    else Deno.env.set("ADMIN_WEBAUTHN_ORIGIN", originalOrigin);
    if (originalRPID === undefined) Deno.env.delete("ADMIN_WEBAUTHN_RP_ID");
    else Deno.env.set("ADMIN_WEBAUTHN_RP_ID", originalRPID);
  }
});
