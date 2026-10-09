// Developer: gengyun
// Purpose: Provide encryption, TOTP, and one-time challenge primitives for administrator factors.

const encoder = new TextEncoder();
const base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function arrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return Uint8Array.from(bytes).buffer as ArrayBuffer;
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function decodeBase64URL(value: string): Uint8Array {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const binary = atob(base64 + "=".repeat((4 - base64.length % 4) % 4));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function encodeBase32(bytes: Uint8Array): string {
  let output = "";
  let buffer = 0;
  let bits = 0;
  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += base32Alphabet[(buffer >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += base32Alphabet[(buffer << (5 - bits)) & 31];
  return output;
}

function decodeBase32(value: string): Uint8Array {
  let buffer = 0;
  let bits = 0;
  const bytes: number[] = [];
  for (const character of value.toUpperCase().replaceAll("=", "")) {
    const digit = base32Alphabet.indexOf(character);
    if (digit < 0) throw new Error("Invalid TOTP secret");
    buffer = (buffer << 5) | digit;
    bits += 5;
    if (bits >= 8) {
      bytes.push((buffer >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return new Uint8Array(bytes);
}

export function newTotpSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return encodeBase32(bytes);
}

export async function totpAt(secret: string, timeMs: number): Promise<string> {
  const counter = BigInt(Math.floor(timeMs / 30_000));
  const message = new Uint8Array(8);
  new DataView(message.buffer).setBigUint64(0, counter, false);
  const key = await crypto.subtle.importKey(
    "raw",
    arrayBuffer(decodeBase32(secret)),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, arrayBuffer(message)),
  );
  const offset = digest[digest.length - 1] & 15;
  const binary = ((digest[offset] & 127) << 24) |
    ((digest[offset + 1] & 255) << 16) |
    ((digest[offset + 2] & 255) << 8) |
    (digest[offset + 3] & 255);
  return String(binary % 1_000_000).padStart(6, "0");
}

export async function matchingTotpCounter(
  secret: string,
  code: string,
  timeMs = Date.now(),
  lastAcceptedCounter = -1,
): Promise<number | null> {
  if (!/^\d{6}$/.test(code)) return null;
  const current = Math.floor(timeMs / 30_000);
  for (const counter of [current - 1, current, current + 1]) {
    if (counter <= lastAcceptedCounter || counter < 0) continue;
    if (await totpAt(secret, counter * 30_000) === code) return counter;
  }
  return null;
}

export async function encryptTotpSecret(
  secret: string,
  configuredKey: string,
): Promise<string> {
  const rawKey = decodeBase64URL(configuredKey);
  if (rawKey.length !== 32) {
    throw new Error("ADMIN_AUTH_FACTOR_ENCRYPTION_KEY must be 32 bytes");
  }
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await crypto.subtle.importKey(
    "raw",
    arrayBuffer(rawKey),
    "AES-GCM",
    false,
    ["encrypt"],
  );
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: arrayBuffer(iv) },
    key,
    arrayBuffer(encoder.encode(secret)),
  );
  return `v1.${encodeBase64URL(iv)}.${
    encodeBase64URL(new Uint8Array(ciphertext))
  }`;
}

export async function decryptTotpSecret(
  ciphertext: string,
  configuredKey: string,
): Promise<string> {
  const [version, encodedIV, encodedCiphertext] = ciphertext.split(".");
  const rawKey = decodeBase64URL(configuredKey);
  if (
    version !== "v1" || !encodedIV || !encodedCiphertext || rawKey.length !== 32
  ) {
    throw new Error("Invalid TOTP secret configuration");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    arrayBuffer(rawKey),
    "AES-GCM",
    false,
    ["decrypt"],
  );
  const iv = decodeBase64URL(encodedIV);
  const encrypted = decodeBase64URL(encodedCiphertext);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: arrayBuffer(iv) },
    key,
    arrayBuffer(encrypted),
  );
  return new TextDecoder().decode(plaintext);
}

export function newChallenge(): string {
  return encodeBase64URL(crypto.getRandomValues(new Uint8Array(32)));
}

export async function hashChallenge(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return encodeBase64URL(new Uint8Array(digest));
}

export function webauthnConfig(): {
  rpID: string;
  origin: string;
  rpName: string;
} {
  const origin = Deno.env.get("ADMIN_WEBAUTHN_ORIGIN")?.trim() ?? "";
  const rpID = Deno.env.get("ADMIN_WEBAUTHN_RP_ID")?.trim().toLowerCase() ?? "";
  const rpName = Deno.env.get("ADMIN_WEBAUTHN_RP_NAME")?.trim() ||
    "Recipe Pals Admin";
  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    throw new Error("ADMIN_WEBAUTHN_ORIGIN must be configured");
  }
  if (
    !rpID || parsed.origin !== origin ||
    (parsed.protocol !== "https:" && parsed.hostname !== "localhost") ||
    !(parsed.hostname === rpID || parsed.hostname.endsWith(`.${rpID}`))
  ) {
    throw new Error("Invalid WebAuthn RP configuration");
  }
  return { rpID, origin, rpName };
}
