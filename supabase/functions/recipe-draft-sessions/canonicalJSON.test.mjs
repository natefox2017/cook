import test from "node:test";
import assert from "node:assert/strict";
import { canonicalHash, canonicalJSON } from "./canonicalJSON.ts";
import { createHash } from "node:crypto";
test("RFC8785 primitive and UTF16 ordering vectors", async () => {
  assert.equal(
    canonicalJSON({ z: -0, a: [null, true, 1e-7, 1e6, 4.5] }),
    '{"a":[null,true,1e-7,1000000,4.5],"z":0}',
  );
  assert.equal(
    canonicalJSON({ "\uE000": 1, "😀": 2, "a": 3 }),
    '{"a":3,"😀":2,"":1}',
  );
  assert.equal(
    await canonicalHash({}),
    "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
  );
  const value = { b: 2, a: "é" };
  assert.equal(
    await canonicalHash(value),
    createHash("sha256").update('{"a":"é","b":2}').digest("hex"),
  );
  assert.equal(
    await canonicalHash(value),
    await canonicalHash({ a: "é", b: 2 }),
  );
  assert.notEqual(await canonicalHash("é"), await canonicalHash("e\u0301"));
});
test("invalid JSON domain and non-execution", () => {
  const cycle = {};
  cycle.a = cycle;
  for (
    const value of [
      NaN,
      Infinity,
      9007199254740992,
      1n,
      undefined,
      () => 1,
      new Date(),
      cycle,
      "\ud800",
      [, 1],
    ]
  ) assert.throws(() => canonicalJSON(value));
  let calls = 0;
  const getter = {};
  Object.defineProperty(getter, "a", {
    enumerable: true,
    get() {
      calls++;
      return 1;
    },
  });
  const toJSON = {
    toJSON() {
      calls++;
      return 1;
    },
  };
  const array = [1];
  Object.defineProperty(array, "map", {
    value() {
      calls++;
      return ["injected"];
    },
  });
  class Evil extends Array {}
  for (const value of [getter, toJSON, array, new Evil(1)]) {
    assert.throws(() => canonicalJSON(value));
  }
  assert.equal(calls, 0);
});
