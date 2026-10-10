// Developer: gengyun
// Purpose: Regression-check dashboard and billing page boundary guards.

import { test } from "node:test";
import assert from "node:assert/strict";
import { hasCompletePage } from "./reportPage.ts";

test("complete rows with exact count are accepted", () => {
  assert.equal(hasCompletePage([], 500, 0), true);
  assert.equal(hasCompletePage([1, 2], 500, 2), true);
});

test("a full requested page is conservatively rejected", () => {
  assert.equal(hasCompletePage(Array(500).fill(null), 500, 500), false);
  assert.equal(hasCompletePage(Array(2000).fill(null), 2000), false);
  assert.equal(hasCompletePage(Array(10000).fill(null), 10000), false);
});

test("server-imposed lower row limits cannot hide missing rows", () => {
  assert.equal(hasCompletePage(Array(1000).fill(null), 10000, 1234), false);
  assert.equal(hasCompletePage(Array(1000).fill(null), Number.MAX_SAFE_INTEGER, 1100), false);
});

test("failed, malformed and null results are never complete", () => {
  assert.equal(hasCompletePage(null, 500, 0), false);
  assert.equal(hasCompletePage(undefined, 500, 0), false);
  assert.equal(hasCompletePage([], 0, 0), false);
  assert.equal(hasCompletePage([], 500, -1), false);
});
