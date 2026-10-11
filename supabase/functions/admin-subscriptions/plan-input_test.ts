import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parsePlanBody } from "./plan-input.ts";
import { AppError } from "../_shared/errors.ts";
const valid = {
  planKey: " pro ",
  displayName: "Pro",
  productId: "recipe.pro",
  platform: "app_store",
  price: 0,
  currency: "usd",
  billingPeriod: "monthly",
  active: false,
  description: null,
};
Deno.test("plan writes retain explicit zero, false and normalized currency", () => {
  const result = parsePlanBody(valid);
  assertEquals(result.price, 0);
  assertEquals(result.active, false);
  assertEquals(result.currency, "USD");
  assertEquals(result.plan_key, "pro");
});
Deno.test("plan writes reject coercion, absent currency and oversized input", () => {
  for (
    const bad of [
      ...[null, "", false, "4.99", -1, Infinity, NaN, {}].map((price) => ({
        ...valid,
        price,
      })),
      ...[undefined, null, "false", 0].map((active) => ({ ...valid, active })),
      ...[undefined, null, "", 123, "US", "USDD", "12A"].map((currency) => ({
        ...valid,
        currency,
      })),
      { ...valid, planKey: {} },
      { ...valid, displayName: "x".repeat(201) },
      { ...valid, description: {} },
      { ...valid, description: "x".repeat(4001) },
    ]
  ) assertThrows(() => parsePlanBody(bad), AppError);
});
