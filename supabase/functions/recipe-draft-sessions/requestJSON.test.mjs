import test from "node:test";
import assert from "node:assert/strict";
import { readRequestJSON } from "./requestJSON.ts";
const request = (body, headers = {}) =>
  new Request("https://unit.test/", {
    method: "POST",
    body,
    headers,
    ...(body instanceof ReadableStream ? { duplex: "half" } : {}),
  });
const fails = async (body, code = "INVALID_INPUT") =>
  assert.rejects(readRequestJSON(request(body)), (e) => e.code === code);
test("bounded scanner detects escaped and nested duplicates", async () => {
  assert.deepEqual(
    await readRequestJSON(request('{"x":[{"a":1}],"s":"}\\""}')),
    { x: [{ a: 1 }], s: '}"' },
  );
  for (
    const body of [
      '{"a":1,"a":2}',
      '{"x":[{"a":1,"\\u0061":2}]}',
      "[]",
      "null",
      "1",
      '{"a":}',
      '{"x":' + "[".repeat(34) + "0" + "]".repeat(34) + "}",
    ]
  ) await fails(body);
  await fails(new Uint8Array([123, 34, 97, 34, 58, 34, 255, 34, 125]));
});
test("32768 byte boundary and lying/chunked length", async () => {
  const body = '{"a":"' + "x".repeat(32760) + '"}';
  assert.equal(new TextEncoder().encode(body).length, 32768);
  assert.equal((await readRequestJSON(request(body))).a.length, 32760);
  await fails(body + " ", "INPUT_TOO_LARGE");
  const stream = new ReadableStream({
    start(c) {
      c.enqueue(new Uint8Array(16000));
      c.enqueue(new Uint8Array(17000));
      c.close();
    },
  });
  await assert.rejects(
    readRequestJSON(request(stream, { "content-length": "1" })),
    (e) => e.code === "INPUT_TOO_LARGE",
  );
});
test("oversize cancellation rejecting or never resolving cannot delay or replace 413", async () => {
  for (
    const cancel of [
      () => Promise.reject(Error("cancel secret")),
      () => new Promise(() => {}),
    ]
  ) {
    const stream = new ReadableStream({
      start(c) {
        c.enqueue(new Uint8Array(32769));
      },
      cancel,
    });
    const timeout = AbortSignal.timeout(1000);
    const result = await Promise.race([
      readRequestJSON(request(stream)).catch((e) => e.code),
      new Promise((resolve) =>
        timeout.addEventListener("abort", () => resolve("HUNG"))
      ),
    ]);
    assert.equal(result, "INPUT_TOO_LARGE");
  }
});
