// Developer: gengyun
// Purpose: Encode and resolve the explicitly versioned admin AI secret protocol.

import { AppError } from "./errors.ts";

export type AISecret = {
  secret_ref: string;
  ciphertext: string;
  nonce: string;
  key_version: number;
};

function encode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decode(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("Invalid encoding");
  const bytes = Uint8Array.from(
    atob(value.replaceAll("-", "+").replaceAll("_", "/")),
    (character) => character.charCodeAt(0),
  );
  if (encode(bytes) !== value) throw new Error("Noncanonical encoding");
  return bytes;
}

async function encryptionKey(
  encodedKey: string | undefined,
): Promise<CryptoKey> {
  try {
    const bytes = decode(encodedKey ?? "");
    if (bytes.length !== 32) throw new Error("Invalid key size");
    return await crypto.subtle.importKey("raw", bytes, "AES-GCM", false, [
      "encrypt",
      "decrypt",
    ]);
  } catch {
    throw new AppError(
      "server_misconfigured",
      "AI secret key is unavailable",
      503,
    );
  }
}

function parameters(
  secretRef: string,
  nonce: Uint8Array<ArrayBuffer>,
): AesGcmParams {
  return {
    name: "AES-GCM",
    iv: nonce,
    additionalData: new TextEncoder().encode(`ai-secrets:v2:${secretRef}`),
    tagLength: 128,
  };
}

export async function encryptAISecret(
  apiKey: string,
  encodedKey = Deno.env.get("COOKAPP_AI_SECRET_KEY_V2"),
): Promise<AISecret> {
  if (!apiKey.trim() || apiKey.length > 8192) {
    throw new AppError(
      "validation_error",
      "A nonempty provider key is required",
      400,
    );
  }
  const key = await encryptionKey(encodedKey);
  const secretRef = crypto.randomUUID();
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    parameters(secretRef, nonce),
    key,
    new TextEncoder().encode(apiKey),
  );
  return {
    secret_ref: secretRef,
    ciphertext: encode(new Uint8Array(ciphertext)),
    nonce: encode(nonce),
    key_version: 2,
  };
}

export async function resolveAISecret(
  secret: AISecret,
  encodedKey = Deno.env.get("COOKAPP_AI_SECRET_KEY_V2"),
): Promise<string> {
  // Legacy v1 is opaque: never guess its format or silently re-encrypt it.
  if (secret.key_version !== 2) {
    throw new AppError(
      "conflict",
      "Saved key has an unsupported version; replace the key explicitly",
      409,
    );
  }
  const key = await encryptionKey(encodedKey);
  try {
    const nonce = decode(secret.nonce);
    if (nonce.length !== 12) throw new Error("Invalid nonce size");
    const plaintext = await crypto.subtle.decrypt(
      parameters(secret.secret_ref, nonce),
      key,
      decode(secret.ciphertext),
    );
    return new TextDecoder("utf-8", { fatal: true }).decode(plaintext);
  } catch {
    // Cipher errors must never reach the generic logger with sensitive values.
    throw new AppError(
      "server_misconfigured",
      "Saved key cannot be resolved",
      503,
    );
  }
}
