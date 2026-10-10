// Developer: gengyun
// Purpose: Test recorded purchase currency boundaries without database or live payments.

import { test } from "node:test";
import assert from "node:assert/strict";
import { RecordedRevenueLedger, isRecordedPurchaseEvent } from "./recordedRevenue.ts";

test("single currency keeps platform totals separate across calendar years", () => {
  const ledger = new RecordedRevenueLedger();
  ledger.record({ price_in_purchased_currency: 4.99, currency: "usd" }, "app_store", "2025-01");
  ledger.record({ price_in_purchased_currency: 8, currency: "USD" }, "play_store", "2026-01");
  const summary = ledger.summary();
  assert.equal(summary.currency, "USD");
  assert.equal(summary.total, 12.99);
  assert.deepEqual(ledger.monthKeys(), ["2025-01", "2026-01"]);
  assert.equal(ledger.monthly("2025-01", summary.currency)?.apple, 4.99);
  assert.equal(ledger.monthly("2026-01", summary.currency)?.android, 8);
});

test("USD and JPY are never combined into fabricated USD revenue", () => {
  const ledger = new RecordedRevenueLedger();
  ledger.record({ price: 4.99, currency: "USD" }, "app_store", "2026-01");
  ledger.record({ price: 1200, currency: "JPY" }, "play_store", "2026-01");
  const summary = ledger.summary();
  assert.equal(summary.currency, null);
  assert.equal(summary.total, null);
  assert.equal(summary.comparable, false);
  assert.equal(ledger.monthly("2026-01", summary.currency), null);
  assert.deepEqual(summary.byCurrency.map((item) => [item.currency, item.total]), [
    ["JPY", 1200], ["USD", 4.99],
  ]);
});

test("missing currency, invalid amounts, and saturated pages fail closed", () => {
  const ledger = new RecordedRevenueLedger();
  ledger.record({ price: 8 }, "app_store", "2026-01");
  ledger.record({ price: -1, currency: "USD" }, "app_store", "2026-01");
  ledger.record({ price: "invalid", currency: "USD" }, "app_store", "2026-01");
  ledger.record({ price: 5, currency: "USD" }, "app_store", "2026-01");
  assert.equal(ledger.summary().incompleteEvents, 3);
  assert.equal(ledger.summary().total, null);
  const capped = new RecordedRevenueLedger();
  capped.record({ price: 3, currency: "USD" }, "app_store", "2026-01");
  assert.equal(capped.summary(true).sourceRowsTruncated, true);
  assert.equal(capped.summary(true).total, null);
});

test("free trial amount does not fabricate recorded money or a currency", () => {
  const ledger = new RecordedRevenueLedger();
  ledger.record({ price: 0 }, "app_store", "2026-01");
  assert.equal(ledger.summary().incompleteEvents, 0);
  assert.equal(ledger.summary().total, null);
});

test("only actual purchase webhooks contribute to recorded sales", () => {
  for (const type of ["INITIAL_PURCHASE", "RENEWAL", "NON_RENEWING_PURCHASE"]) {
    assert.equal(isRecordedPurchaseEvent(type), true);
  }
  for (const type of ["PRODUCT_CHANGE", "CANCELLATION", "REFUND_REVERSED", "TEST", "EXPIRATION", null]) {
    assert.equal(isRecordedPurchaseEvent(type), false);
  }
  // A product-change event may accompany a separate renewal; it must not
  // be treated as a second monetary purchase.
  const ledger = new RecordedRevenueLedger();
  for (const event of [
    { event_type: "PRODUCT_CHANGE", price: 10, currency: "USD" },
    { event_type: "RENEWAL", price: 10, currency: "USD" },
  ]) {
    if (isRecordedPurchaseEvent(event.event_type)) {
      ledger.record(event, "app_store", "2026-10");
    }
  }
  assert.equal(ledger.summary().total, 10);
});
