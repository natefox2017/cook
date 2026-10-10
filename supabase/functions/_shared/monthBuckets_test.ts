// Developer: gengyun
// Purpose: Guard financial reports against collisions between the same month in different years.

import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { displayUTCMonth, utcMonthKey } from "./monthBuckets.ts";

Deno.test("the same calendar month in different years has distinct keys", () => {
  assertEquals(utcMonthKey("2025-01-01T12:00:00Z"), "2025-01");
  assertEquals(utcMonthKey("2026-01-01T12:00:00Z"), "2026-01");
  const buckets = new Map<string, number>();
  for (const [date, amount] of [
    ["2025-01-15T13:00:00Z", 100],
    ["2026-01-15T13:00:00Z", 200],
  ] as const) {
    const key = utcMonthKey(date);
    buckets.set(key, (buckets.get(key) ?? 0) + amount);
  }
  assertEquals(buckets.size, 2);
  assertEquals(buckets.get("2025-01"), 100);
  assertEquals(buckets.get("2026-01"), 200);
});

Deno.test("year_month date and month strings both use stable UTC keys", () => {
  assertEquals(utcMonthKey("2026-02"), "2026-02");
  assertEquals(utcMonthKey("2026-02-01"), "2026-02");
  assertEquals(displayUTCMonth("2026-02"), "Feb 2026");
});

Deno.test("UTC boundaries respect explicit source offsets", () => {
  assertEquals(utcMonthKey("2026-01-01T00:30:00+09:00"), "2025-12");
  assertEquals(utcMonthKey("2025-12-31T23:30:00-08:00"), "2026-01");
});

Deno.test("invalid or ambiguous dates fail instead of silently merging buckets", () => {
  for (const value of [
    "Jan", "2026-13", "2026-00", "2026", "not-a-date",
    "2026-01-01T12:00:00",
  ]) {
    assertThrows(() => utcMonthKey(value), Error, "Invalid report month");
  }
});
