import { AppError } from "../_shared/errors.ts";
import {
  pageResult,
  parseUsersQuery,
  profileMatchesSubscription,
  userDetail,
  userSummary,
  type PlanRow,
  type ProfileRow,
  type SubscriptionRow,
} from "./model.ts";

const profile: ProfileRow = {
  id: "00000000-0000-4000-8000-000000000001",
  email: "user@example.com",
  display_name: "Example User",
  avatar: null,
  created_at: "2026-01-01T00:00:00.000Z",
  account_status: "active",
  registration_provider: "email",
  device_type: "ios",
  registration_ip: "203.0.113.10",
};

const subscription: SubscriptionRow = {
  user_id: profile.id,
  plan: null,
  product_id: "product.monthly",
  store: "app_store",
  status: "active",
};

const monthlyPlan: PlanRow = {
  plan_key: "pro_monthly",
  product_id: "product.monthly",
  platform: "app_store",
  billing_period: "monthly",
};

Deno.test("pagination is bounded and handles empty result pages", () => {
  const parsed = parseUsersQuery(new URLSearchParams("page=2&pageSize=1000"));
  if (parsed.page !== 2 || parsed.pageSize !== 100) throw new Error("pagination bounds failed");
  const empty = pageResult([], 0, parsed.page, parsed.pageSize);
  if (empty.total !== 0 || empty.data.length !== 0) throw new Error("empty page failed");
});

Deno.test("invalid filter values do not broaden into arbitrary filters", () => {
  let errorCode: string | null = null;
  try {
    parseUsersQuery(new URLSearchParams("subscription=secret&status=all"));
  } catch (error) {
    if (error instanceof AppError) errorCode = error.code;
  }
  if (errorCode !== "validation_error") throw new Error("invalid filter was accepted or misclassified");
  if (parseUsersQuery(new URLSearchParams("status=all")).status !== null) throw new Error("all filter failed");
});

Deno.test("no subscription maps to free and leaves plan fields null", () => {
  const user = userSummary(profile, undefined, undefined, null);
  if (user.subscription !== "free" || user.subscriptionPlan !== null) throw new Error("no-subscription mapping failed");
  if (user.subscriptionBillingPeriod !== null || user.subscriptionStatus !== null) throw new Error("empty subscription fields were invented");
});

Deno.test("monthly and yearly periods come from their plan rows", () => {
  const yearly: PlanRow = { ...monthlyPlan, plan_key: "pro_yearly", billing_period: "yearly" };
  if (userSummary(profile, subscription, monthlyPlan, null).subscriptionBillingPeriod !== "monthly") {
    throw new Error("monthly billing period was lost");
  }
  if (userSummary(profile, subscription, yearly, null).subscriptionBillingPeriod !== "yearly") {
    throw new Error("yearly billing period was lost");
  }
  if (!profileMatchesSubscription(subscription, yearly, "pro")) throw new Error("paid plan filter failed");
});

Deno.test("last login IP stays null without user-linked auth history", () => {
  const detail = userDetail(profile, undefined, undefined, { last_sign_in_at: "2026-02-01T00:00:00.000Z" }, []);
  if (detail.lastLoginIp !== null) throw new Error("login IP must stay unknown");
  if (detail.registrationIp !== profile.registration_ip) throw new Error("registration IP was not preserved separately");
});
