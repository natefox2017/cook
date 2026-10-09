import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2.117.3";
import { authCorsHeaders, handleCors } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { requireAdminRole } from "../_shared/admin-role.ts";
import { requireAdminSession } from "../_shared/admin-session.ts";
import {
  pageResult,
  parseUsersQuery,
  profileMatchesSubscription,
  userDetail,
  userSummary,
  type AuthUserSummary,
  type PlanRow,
  type ProfileRow,
  type SubscriptionRow,
  type UserPayment,
} from "./model.ts";

const PROFILE_COLUMNS = [
  "id",
  "email",
  "display_name",
  "avatar",
  "created_at",
  "account_status",
  "registration_provider",
  "device_type",
  "registration_ip",
].join(",");
const BATCH_SIZE = 500;

type UserFilters = {
  query: string;
  status: string | null;
  registrationProvider: string | null;
  deviceType: string | null;
};

function routeUserId(req: Request): string | null {
  const parts = new URL(req.url).pathname.split("/").filter(Boolean);
  const functionIndex = parts.lastIndexOf("admin-users");
  if (functionIndex < 0) throw new AppError("not_found", "Not found", 404);
  const suffix = parts.slice(functionIndex + 1);
  if (suffix.length > 1) throw new AppError("not_found", "Not found", 404);
  return suffix[0] ?? null;
}

function profileQuery(db: SupabaseClient, columns: string, filters: UserFilters) {
  let query = db.from("profiles").select(columns, { count: "exact" });
  if (filters.status) query = query.eq("account_status", filters.status);
  if (filters.registrationProvider) query = query.eq("registration_provider", filters.registrationProvider);
  if (filters.deviceType) query = query.eq("device_type", filters.deviceType);
  if (filters.query) {
    const pattern = `%${filters.query}%`;
    query = query.or(`display_name.ilike.${pattern},email.ilike.${pattern}`);
  }
  return query;
}

function throwDatabaseError(message: string): never {
  throw new AppError("internal_error", message, 500);
}

async function fetchProfileIds(db: SupabaseClient, filters: UserFilters): Promise<string[]> {
  const ids: string[] = [];
  for (let offset = 0; ; offset += BATCH_SIZE) {
    const { data, error } = await profileQuery(db, "id,created_at", filters)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(offset, offset + BATCH_SIZE - 1);
    if (error) throwDatabaseError("Failed to load users");
    const rows = (data ?? []) as unknown as Array<Pick<ProfileRow, "id" | "created_at">>;
    ids.push(...rows.map((row) => row.id));
    if (rows.length < BATCH_SIZE) return ids;
  }
}

async function fetchProfiles(db: SupabaseClient, ids: string[]): Promise<ProfileRow[]> {
  if (!ids.length) return [];
  const rows: ProfileRow[] = [];
  for (const batch of chunks(ids, BATCH_SIZE)) {
    const { data, error } = await db.from("profiles").select(PROFILE_COLUMNS).in("id", batch);
    if (error) throwDatabaseError("Failed to load users");
    rows.push(...(data ?? []) as unknown as ProfileRow[]);
  }
  const byId = new Map(rows.map((row) => [row.id, row]));
  return ids.flatMap((id) => {
    const profile = byId.get(id);
    return profile ? [profile] : [];
  });
}

async function fetchSubscriptions(db: SupabaseClient, userIds: string[]): Promise<SubscriptionRow[]> {
  const subscriptions: SubscriptionRow[] = [];
  for (const batch of chunks(userIds, BATCH_SIZE)) {
    const { data, error } = await db.from("subscriptions")
      .select("user_id,plan,product_id,store,status")
      .in("user_id", batch);
    if (error) throwDatabaseError("Failed to load subscription summaries");
    subscriptions.push(...(data ?? []) as SubscriptionRow[]);
  }
  return subscriptions;
}

async function fetchPlans(db: SupabaseClient, subscriptions: SubscriptionRow[]): Promise<PlanRow[]> {
  const productIds = [...new Set(subscriptions.flatMap((row) => row.product_id ? [row.product_id] : []))];
  const planKeys = [...new Set(subscriptions.flatMap((row) => row.plan ? [row.plan] : []))];
  const plans = new Map<string, PlanRow>();

  for (const batch of chunks(productIds, BATCH_SIZE)) {
    const { data, error } = await db.from("subscription_plans")
      .select("plan_key,product_id,platform,billing_period")
      .in("product_id", batch);
    if (error) throwDatabaseError("Failed to load subscription plans");
    for (const plan of (data ?? []) as PlanRow[]) plans.set(`${plan.platform}:${plan.product_id}`, plan);
  }
  for (const batch of chunks(planKeys, BATCH_SIZE)) {
    const { data, error } = await db.from("subscription_plans")
      .select("plan_key,product_id,platform,billing_period")
      .in("plan_key", batch);
    if (error) throwDatabaseError("Failed to load subscription plans");
    for (const plan of (data ?? []) as PlanRow[]) plans.set(`${plan.platform}:${plan.product_id}`, plan);
  }
  return [...plans.values()];
}

function matchingPlan(subscription: SubscriptionRow | undefined, plans: PlanRow[]): PlanRow | undefined {
  if (!subscription) return undefined;
  if (subscription.product_id) {
    const matchingProduct = plans.filter((plan) => plan.product_id === subscription.product_id);
    const platform = subscription.store === "app_store" || subscription.store === "play_store"
      ? subscription.store
      : null;
    const candidates = platform
      ? matchingProduct.filter((plan) => plan.platform === platform)
      : matchingProduct;
    if (candidates.length === 1) return candidates[0];
    if (candidates.length > 1 && candidates.every((plan) => plan.plan_key === candidates[0].plan_key && plan.billing_period === candidates[0].billing_period)) {
      return candidates[0];
    }
  }
  if (!subscription.plan) return undefined;
  const matchingKey = plans.filter((plan) => plan.plan_key === subscription.plan);
  if (matchingKey.length === 1) return matchingKey[0];
  if (matchingKey.length > 1 && matchingKey.every((plan) => plan.billing_period === matchingKey[0].billing_period)) {
    return matchingKey[0];
  }
  return undefined;
}

async function filteredUserIds(
  db: SupabaseClient,
  filters: UserFilters,
  subscriptionFilter: "free" | "pro" | "lifetime",
): Promise<string[]> {
  const profileIds = await fetchProfileIds(db, filters);
  if (!profileIds.length) return [];

  const subscriptions = await fetchSubscriptions(db, profileIds);
  const plans = await fetchPlans(db, subscriptions);
  const subscriptionsByUser = new Map(subscriptions.map((row) => [row.user_id, row]));
  return profileIds.filter((id) => {
    const subscription = subscriptionsByUser.get(id);
    return profileMatchesSubscription(subscription, matchingPlan(subscription, plans), subscriptionFilter);
  });
}

async function authUsers(db: SupabaseClient, userIds: string[]): Promise<Map<string, AuthUserSummary>> {
  const users = new Map<string, AuthUserSummary>();
  for (const batch of chunks(userIds, 10)) {
    const results = await Promise.all(batch.map(async (id) => {
      const { data, error } = await db.auth.admin.getUserById(id);
      if (error) {
        if (error.status === 404 || error.code === "user_not_found") return [id, null] as const;
        throwDatabaseError("Failed to load user authentication summary");
      }
      return [id, data.user as AuthUserSummary | null] as const;
    }));
    for (const [id, user] of results) if (user) users.set(id, user);
  }
  return users;
}

function chunks<T>(values: T[], size: number): T[][] {
  const batches: T[][] = [];
  for (let index = 0; index < values.length; index += size) batches.push(values.slice(index, index + size));
  return batches;
}

function userSubscriptionMaps(subscriptions: SubscriptionRow[], plans: PlanRow[]) {
  const byUser = new Map(subscriptions.map((row) => [row.user_id, row]));
  const planByUser = new Map<string, PlanRow>();
  for (const row of subscriptions) {
    const plan = matchingPlan(row, plans);
    if (plan) planByUser.set(row.user_id, plan);
  }
  return { byUser, planByUser };
}

async function listUsers(db: SupabaseClient, url: URL, req: Request): Promise<Response> {
  const parsed = parseUsersQuery(url.searchParams);
  const filters = {
    query: parsed.query,
    status: parsed.status,
    registrationProvider: parsed.registrationProvider,
    deviceType: parsed.deviceType,
  };
  const offset = (parsed.page - 1) * parsed.pageSize;
  let profiles: ProfileRow[];
  let total: number;

  if (parsed.subscription) {
    const userIds = await filteredUserIds(db, filters, parsed.subscription);
    total = userIds.length;
    const pageIds = userIds.slice(offset, offset + parsed.pageSize);
    profiles = await fetchProfiles(db, pageIds);
    profiles.sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id));
  } else {
    const { data, error, count } = await profileQuery(db, PROFILE_COLUMNS, filters)
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(offset, offset + parsed.pageSize - 1);
    if (error) throwDatabaseError("Failed to load users");
    profiles = (data ?? []) as unknown as ProfileRow[];
    total = count ?? 0;
  }

  const ids = profiles.map((profile) => profile.id);
  const subscriptions = await fetchSubscriptions(db, ids);
  const plans = await fetchPlans(db, subscriptions);
  const subscriptionMaps = userSubscriptionMaps(subscriptions, plans);
  const authUserMap = await authUsers(db, ids);
  const users = profiles.map((profile) => userSummary(
    profile,
    subscriptionMaps.byUser.get(profile.id),
    subscriptionMaps.planByUser.get(profile.id),
    authUserMap.get(profile.id) ?? null,
  ));
  return json(pageResult(users, total, parsed.page, parsed.pageSize), 200, authCorsHeaders(req));
}

async function userById(db: SupabaseClient, id: string, req: Request): Promise<Response> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    throw new AppError("not_found", "User not found", 404);
  }
  const { data, error } = await db.from("profiles").select(PROFILE_COLUMNS).eq("id", id).maybeSingle();
  if (error) throwDatabaseError("Failed to load user details");
  if (!data) throw new AppError("not_found", "User not found", 404);
  const profile = data as unknown as ProfileRow;
  const subscriptions = await fetchSubscriptions(db, [id]);
  const plans = await fetchPlans(db, subscriptions);
  const subscriptionMaps = userSubscriptionMaps(subscriptions, plans);
  const authUserMap = await authUsers(db, [id]);
  const { data: paymentRows, error: paymentError } = await db.from("payment_transactions")
    .select("id,event_type,product_id,store,gross_amount,currency,environment,purchase_at,created_at")
    .eq("user_id", id)
    .order("purchase_at", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false });
  if (paymentError) throwDatabaseError("Failed to load user payment history");
  const payments: UserPayment[] = (paymentRows ?? []).map((row) => ({
    id: row.id as string,
    eventType: row.event_type as string,
    productId: row.product_id as string | null,
    store: row.store as string | null,
    amount: row.gross_amount == null ? null : Number(row.gross_amount),
    currency: row.currency as string | null,
    environment: row.environment as string | null,
    purchasedAt: (row.purchase_at ?? row.created_at) as string,
  }));
  return json(userDetail(
    profile,
    subscriptionMaps.byUser.get(id),
    subscriptionMaps.planByUser.get(id),
    authUserMap.get(id) ?? null,
    payments,
  ), 200, authCorsHeaders(req));
}

Deno.serve(async (req) => {
  const cors = authCorsHeaders(req);
  const preflight = handleCors(req, "auth");
  if (preflight) return preflight;

  try {
    if (req.method !== "GET") throw new AppError("method_not_allowed", "Method not allowed", 405);
    const userId = routeUserId(req);
    const session = await requireAdminSession(req);
    requireAdminRole(session.role, ["owner", "admin"]);
    const db = createServiceClient();
    return userId
      ? await userById(db, userId, req)
      : await listUsers(db, new URL(req.url), req);
  } catch (error) {
    return errorResponse(error, cors);
  }
});
