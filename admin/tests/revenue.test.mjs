import test from "node:test";
import assert from "node:assert/strict";
import { parseRevenue } from "../src/revenue.ts";

const current = () => ({
  stats: { mrr: null, appleRevenue: 10, androidRevenue: 0, currency: "USD",
    byCurrency: [{ currency: "USD", appleRevenue: 10, androidRevenue: 0, total: 10 }],
    incompleteEvents: 0, sourceRowsTruncated: false, activePaid: 1 },
  series: [{ month: "2026-10", apple: 10, android: 0, total: 10 }],
});

test("preserves current single and mixed-currency responses without inventing totals", () => {
  const value = current();
  assert.equal(parseRevenue(value), value);
  Object.assign(value.stats, { currency: null, appleRevenue: null, androidRevenue: null });
  assert.equal(parseRevenue(value), value);
});

test("rejects legacy response and malformed fields before rendering", () => {
  const legacy = { stats: { mrr: 10, appleRevenue: 10, androidRevenue: 0, activePaid: 1 }, series: [] };
  for (const value of [legacy, null, {}, { ...current(), series: null },
    { ...current(), stats: { ...current().stats, byCurrency: [null] } },
    { ...current(), stats: { ...current().stats, currency: "invalid" } },
    { ...current(), stats: { ...current().stats, appleRevenue: Infinity } }]) {
    assert.throws(() => parseRevenue(value), /Revenue unavailable/);
  }
});
