import { AppError } from "../_shared/errors.ts";

export type BillingPeriod = "monthly" | "yearly" | "lifetime";
export type SubscriptionTier = "free" | "pro" | "lifetime";

export type ProfileRow = {
  id: string;
  email: string | null;
  display_name: string | null;
  avatar: string | null;
  created_at: string;
  account_status: "active" | "suspended" | "deleted";
  registration_provider: "apple" | "google" | "email" | "unknown" | null;
  device_type: "ios" | "android" | "web" | "unknown" | null;
  registration_ip: string | null;
};

export type SubscriptionRow = {
  user_id: string;
  plan: string | null;
  product_id: string | null;
  store: string | null;
  status: string;
};

export type PlanRow = {
  plan_key: string;
  product_id: string;
  platform: "app_store" | "play_store";
  billing_period: BillingPeriod;
};

export type AuthUserSummary = {
  email?: string | null;
  last_sign_in_at?: string | null;
};

export type UserPayment = {
  id: string;
  eventType: string;
  productId: string | null;
  store: string | null;
  amount: number | null;
  currency: string | null;
  environment: string | null;
  purchasedAt: string;
};

export function parseUsersQuery(params: URLSearchParams) {
  const page = parsePositiveInteger(params.get("page"), 1);
  const pageSize = Math.min(parsePositiveInteger(params.get("pageSize"), 20), 100);
  const query = (params.get("q") ?? "").replace(/[\\%_,()*]/g, " ").trim().slice(0, 100);
  const status = parseFilter(params.get("status"), ["active", "suspended", "deleted"] as const);
  const registrationProvider = parseFilter(
    params.get("registrationProvider"),
    ["apple", "google", "email", "unknown"] as const,
  );
  const subscription = parseFilter(params.get("subscription"), ["free", "pro", "lifetime"] as const);
  const deviceType = parseFilter(params.get("deviceType"), ["ios", "android", "web", "unknown"] as const);

  return { page, pageSize, query, status, registrationProvider, subscription, deviceType };
}

export function profileMatchesSubscription(
  subscription: SubscriptionRow | undefined,
  plan: PlanRow | undefined,
  filter: SubscriptionTier,
): boolean {
  return subscriptionTier(subscription, plan) === filter;
}

export function subscriptionTier(
  subscription: SubscriptionRow | undefined,
  plan: PlanRow | undefined,
): SubscriptionTier {
  if (!subscription || !["active", "trialing"].includes(subscription.status)) return "free";
  if (plan?.billing_period === "lifetime" || subscription.plan === "lifetime") return "lifetime";
  return "pro";
}

export function userSummary(
  profile: ProfileRow,
  subscription: SubscriptionRow | undefined,
  plan: PlanRow | undefined,
  authUser: AuthUserSummary | null,
) {
  return {
    id: profile.id,
    email: profile.email ?? authUser?.email ?? "",
    displayName: profile.display_name?.trim() || "Unknown",
    avatarUrl: profile.avatar,
    subscription: subscriptionTier(subscription, plan),
    createdAt: profile.created_at,
    status: profile.account_status,
    registrationProvider: profile.registration_provider ?? "unknown",
    deviceType: profile.device_type ?? "unknown",
    registrationCountryCode: null,
    lastLoginAt: authUser?.last_sign_in_at ?? null,
    // No user-linked login IP history is available to this function. Never substitute registration_ip.
    lastLoginIp: null,
    subscriptionPlan: plan?.plan_key ?? subscription?.plan ?? null,
    subscriptionBillingPeriod: plan?.billing_period ?? null,
    subscriptionStatus: subscription?.status ?? null,
  };
}

export function userDetail(
  profile: ProfileRow,
  subscription: SubscriptionRow | undefined,
  plan: PlanRow | undefined,
  authUser: AuthUserSummary | null,
  payments: UserPayment[],
) {
  return {
    ...userSummary(profile, subscription, plan, authUser),
    registrationIp: profile.registration_ip,
    payments,
  };
}

export function pageResult<T>(data: T[], total: number, page: number, pageSize: number) {
  return { data, total, page, pageSize };
}

function parsePositiveInteger(value: string | null, fallback: number) {
  if (!value || !/^[0-9]+$/.test(value)) return fallback;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function parseFilter<const T extends readonly string[]>(value: string | null, allowed: T): T[number] | null {
  if (!value || value === "all") return null;
  const match = allowed.find((option) => option === value);
  if (match) return match;
  throw new AppError("validation_error", "Invalid user filter", 400);
}
