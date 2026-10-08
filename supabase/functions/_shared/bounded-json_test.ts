// Developer: RecipePouch
// Purpose: Regression coverage for bounded public-facing admin JSON requests.

import { readBoundedJSONObject } from "./bounded-json.ts";
import { AppError } from "./errors.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function request(body?: BodyInit | null, headers?: HeadersInit): Request {
  return new Request("https://example.invalid/functions/v1/admin-auth/login", {
    method: "POST",
    ...(body === undefined ? {} : { body }),
    headers,
  });
}

async function expectError(
  req: Request,
  maxBytes: number,
  status: number,
): Promise<void> {
  try {
    await readBoundedJSONObject(req, maxBytes);
  } catch (error) {
    assert(error instanceof AppError, "Expected an API input error.");
    assert(error.status === status, `Expected HTTP ${status}, received ${error.status}`);
    return;
  }
  throw new Error("Invalid request was accepted.");
}

Deno.test("small valid JSON objects pass unchanged", async () => {
  const input = { username: "cook-owner", password: "example-pass" };
  const parsed = await readBoundedJSONObject(request(JSON.stringify(input)), 256);
  assert(parsed.username === input.username && parsed.password === input.password,
    "Valid admin login fields changed");
});

Deno.test("honest or dishonest Content-Length cannot bypass the byte limit", async () => {
  await expectError(request("{}", { "content-length": "999999" }), 32, 413);
  // An attacker can omit a length or underreport it; the stream limit remains authoritative.
  await expectError(request(JSON.stringify({ payload: "x".repeat(500) }),
    { "content-length": "1" }), 128, 413);
});

Deno.test("streaming body is rejected one byte past its exact cap", async () => {
  const raw = JSON.stringify({ note: "a".repeat(120) });
  assert(new TextEncoder().encode(raw).byteLength === 131, "Fixture size changed.");
  await readBoundedJSONObject(request(raw), 131);
  await expectError(request(raw), 130, 413);
});

Deno.test("malformed JSON, arrays and missing bodies fail as validation errors", async () => {
  await expectError(request('{"invalid":'), 128, 400);
  await expectError(request('["not an object"]'), 128, 400);
  await expectError(request("null"), 128, 400);
  await expectError(request(undefined), 128, 400);
});

Deno.test("invalid UTF-8 bytes cannot become a login object", async () => {
  const bad = new Blob([new Uint8Array([0xff, 0x80, 0x00])]);
  await expectError(request(bad), 32, 400);
});

Deno.test("the parser rejects invalid size configurations", async () => {
  try {
    await readBoundedJSONObject(request("{}"), 0);
    throw new Error("Invalid parser limit was accepted");
  } catch (error) {
    assert(error instanceof Error && error.message === "Invalid request body size limit.",
      "Expected a local configuration error.");
  }
});
