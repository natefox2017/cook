import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";
import { handleCors, publicCorsHeaders } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { requireAdminSession } from "../_shared/admin-session.ts";
import { log } from "../_shared/logger.ts";
import { authorizeSubscriptionRoute } from "./authorization.ts";
import { utcMonthKey } from "../_shared/monthBuckets.ts";

type Platform = "app_store" | "play_store";

function routeParts(req: Request): string[] {
  const parts = new URL(req.url).pathname.split("/").filter(Boolean);
  const index = parts.findIndex((part) => part === "admin-subscriptions");
  return index >= 0 ? parts.slice(index + 1) : parts.slice(-2);
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json();
    return body && typeof body === "object"
      ? body as Record<string, unknown>
      : {};
  } catch {
    throw new AppError("validation_error", "Invalid JSON body", 400);
  }
}

function mapPlan(row: Record<string, unknown>) {
  return {
    id: row.id,
    planKey: row.plan_key,
    displayName: row.display_name,
    platform: row.platform,
    productId: row.product_id,
    price: Number(row.price),
    currency: row.currency,
    billingPeriod: row.billing_period,
    active: Boolean(row.active),
    description: row.description ?? null,
    updatedAt: row.updated_at,
  };
}

function parsePlanBody(body: Record<string, unknown>) {
  const planKey = String(body.planKey ?? "").trim();
  const displayName = String(body.displayName ?? "").trim();
  const platform = String(body.platform ?? "").trim() as Platform;
  const productId = String(body.productId ?? "").trim();
  const currency = String(body.currency ?? "USD").trim().toUpperCase() ||
    "USD";
  const billingPeriod = String(body.billingPeriod ?? "").trim();
  const description = body.description == null || body.description === ""
    ? null
    : String(body.description);
  const price = Number(body.price);
  const active = Boolean(body.active ?? true);

  if (!planKey || !displayName || !productId) {
    throw new AppError(
      "validation_error",
      "planKey, displayName, and productId are required",
      400,
    );
  }
  if (platform !== "app_store" && platform !== "play_store") {
    throw new AppError(
      "validation_error",
      "platform must be app_store or play_store",
      400,
    );
  }
  if (!["monthly", "yearly", "lifetime"].includes(billingPeriod)) {
    throw new AppError("validation_error", "invalid billingPeriod", 400);
  }
  if (!Number.isFinite(price) || price < 0) {
    throw new AppError(
      "validation_error",
      "price must be a non-negative number",
      400,
    );
  }

  return {
    plan_key: planKey,
    display_name: displayName,
    platform,
    product_id: productId,
    price,
    currency,
    billing_period: billingPeriod,
    active,
    description,
  };
}

function mapStatus(status: string): string {
  return status === "none" ? "expired" : status;
}

function mapPlanLabel(plan: string | null, productId: string | null): string {
  if (plan === "pro" || plan === "lifetime" || plan === "free") return plan;
  const normalizedProductId = (productId ?? "").toLowerCase();
  if (normalizedProductId.includes("lifetime")) return "lifetime";
  if (
    normalizedProductId.includes("pro") ||
    normalizedProductId.includes("monthly") ||
    normalizedProductId.includes("yearly")
  ) {
    return "pro";
  }
  return plan || "free";
}

type AdminSession = Awaited<ReturnType<typeof requireAdminSession>>;
type AdminClient = ReturnType<typeof createServiceClient>;

export interface AdminSubscriptionsDependencies {
  requireAdminSession: (req: Request) => Promise<AdminSession>;
  createServiceClient: () => AdminClient;
}

const productionDependencies: AdminSubscriptionsDependencies = {
  requireAdminSession,
  createServiceClient,
};

export async function handleRequest(
  req: Request,
  dependencies: AdminSubscriptionsDependencies = productionDependencies,
): Promise<Response> {
  const cors = handleCors(req, "public");
  if (cors) return cors;

  try {
    const session = await dependencies.requireAdminSession(req);
    const parts = routeParts(req);
    const method = req.method.toUpperCase();
    const resource = (parts[0] ?? "").toLowerCase();
    const id = parts[1];

    authorizeSubscriptionRoute(session.role, resource, method);

    const admin = dependencies.createServiceClient();

    if (resource === "plans" && method === "GET" && !id) {
      const { data, error } = await admin
        .from("subscription_plans")
        .select("*")
        .order("plan_key")
        .order("platform");
      if (error) {
        throw new AppError("internal_error", "Failed to load plans", 500);
      }
      return json(
        (data ?? []).map((row) => mapPlan(row as Record<string, unknown>)),
        200,
        publicCorsHeaders,
      );
    }

    if (resource === "plans" && method === "POST" && !id) {
      const payload = parsePlanBody(await readJson(req));
      const { data, error } = await admin
        .from("subscription_plans")
        .insert(payload)
        .select("*")
        .single();
      if (error) {
        throw new AppError(
          error.code === "23505" ? "conflict" : "internal_error",
          error.code === "23505"
            ? "Plan already exists"
            : "Failed to create plan",
          error.code === "23505" ? 409 : 500,
        );
      }
      log("info", "admin_plan_created", { id: data.id });
      return json(
        mapPlan(data as Record<string, unknown>),
        201,
        publicCorsHeaders,
      );
    }

    if (resource === "plans" && method === "PUT" && id) {
      const payload = parsePlanBody(await readJson(req));
      const { data, error } = await admin
        .from("subscription_plans")
        .update(payload)
        .eq("id", id)
        .select("*")
        .maybeSingle();
      if (error) {
        throw new AppError("internal_error", "Failed to update plan", 500);
      }
      if (!data) throw new AppError("not_found", "Plan not found", 404);
      return json(
        mapPlan(data as Record<string, unknown>),
        200,
        publicCorsHeaders,
      );
    }

    if (resource === "plans" && method === "DELETE" && id) {
      const { error, count } = await admin
        .from("subscription_plans")
        .delete({ count: "exact" })
        .eq("id", id);
      if (error) {
        throw new AppError("internal_error", "Failed to delete plan", 500);
      }
      if (!count) throw new AppError("not_found", "Plan not found", 404);
      return json({ ok: true }, 200, publicCorsHeaders);
    }

    if (resource === "records" && method === "GET") {
      const url = new URL(req.url);
      const platform = url.searchParams.get("platform");
      let query = admin
        .from("subscriptions")
        .select(
          "user_id, product_id, plan, status, store, expires_at, created_at, updated_at",
        )
        .order("updated_at", { ascending: false })
        .limit(500);
      if (platform === "app_store" || platform === "play_store") {
        query = query.eq("store", platform);
      }
      const { data, error } = await query;
      if (error) {
        throw new AppError(
          "internal_error",
          "Failed to load subscriptions",
          500,
        );
      }

      const userIds = [
        ...new Set((data ?? []).map((row) => row.user_id as string)),
      ];
      const profileMap = new Map<
        string,
        { display_name: string | null; email: string | null }
      >();
      if (userIds.length) {
        const { data: profiles, error: profileError } = await admin
          .from("profiles")
          .select("id, display_name, email")
          .in("id", userIds);
        if (profileError) {
          throw new AppError(
            "internal_error",
            "Failed to load profile data",
            500,
          );
        }
        for (const profile of profiles ?? []) {
          profileMap.set(profile.id as string, {
            display_name: profile.display_name as string | null,
            email: profile.email as string | null,
          });
        }
      }

      const rows = (data ?? []).map((row) => {
        const profile = profileMap.get(row.user_id as string);
        const store = row.store === "app_store" || row.store === "play_store"
          ? row.store
          : null;
        return {
          id: row.user_id,
          user: {
            id: row.user_id,
            displayName: profile?.display_name || "Unknown",
            email: profile?.email || "",
          },
          plan: mapPlanLabel(
            row.plan as string | null,
            row.product_id as string | null,
          ),
          status: mapStatus(String(row.status ?? "expired")),
          platform: store,
          productId: row.product_id ?? null,
          amount: null as number | null,
          currency: null as string | null,
          startDate: String(row.created_at).slice(0, 10),
          expirationDate: row.expires_at
            ? String(row.expires_at).slice(0, 10)
            : null,
        };
      });

      if (userIds.length) {
        const { data: events, error: eventError } = await admin
          .from("purchase_events")
          .select("user_id, product_id, store, raw_event, created_at")
          .in("user_id", userIds)
          .order("created_at", { ascending: false })
          .limit(2000);
        if (eventError) {
          throw new AppError(
            "internal_error",
            "Failed to load purchase data",
            500,
          );
        }
        const latest = new Map<string, { amount: number; currency: string }>();
        for (const event of events ?? []) {
          const key = `${event.user_id}:${event.product_id ?? ""}`;
          if (latest.has(key)) continue;
          const raw = (event.raw_event ?? {}) as Record<string, unknown>;
          const amount = Number(
            raw.price_in_purchased_currency ?? raw.price ?? NaN,
          );
          const currency = String(raw.currency ?? "USD");
          if (Number.isFinite(amount)) latest.set(key, { amount, currency });
        }
        for (const row of rows) {
          const purchase = latest.get(`${row.user.id}:${row.productId ?? ""}`);
          if (purchase) {
            row.amount = purchase.amount;
            row.currency = purchase.currency;
          }
        }
      }

      return json(rows, 200, publicCorsHeaders);
    }

    if (resource === "revenue" && method === "GET") {
      const url = new URL(req.url);
      const platform = url.searchParams.get("platform");
      let query = admin
        .from("purchase_events")
        .select("store, raw_event, created_at, event_type")
        .order("created_at", { ascending: true })
        .limit(5000);
      if (platform === "app_store" || platform === "play_store") {
        query = query.eq("store", platform);
      }
      const { data, error } = await query;
      if (error) {
        throw new AppError("internal_error", "Failed to load revenue", 500);
      }

      const paidTypes = new Set([
        "INITIAL_PURCHASE",
        "RENEWAL",
        "NON_RENEWING_PURCHASE",
        "PRODUCT_CHANGE",
      ]);
      const byMonth = new Map<
        string,
        { apple: number; android: number; order: number }
      >();
      let appleRevenue = 0;
      let androidRevenue = 0;

      for (const event of data ?? []) {
        const type = String(event.event_type ?? "").toUpperCase();
        if (!paidTypes.has(type)) continue;
        const raw = (event.raw_event ?? {}) as Record<string, unknown>;
        const amount = Number(
          raw.price_in_purchased_currency ?? raw.price ?? 0,
        );
        if (!Number.isFinite(amount) || amount <= 0) continue;
        const createdAt = String(event.created_at);
        const key = utcMonthKey(createdAt);
        const date = new Date(createdAt);
        const order = date.getUTCFullYear() * 12 + date.getUTCMonth();
        const bucket = byMonth.get(key) ?? { apple: 0, android: 0, order };
        if (event.store === "app_store") {
          bucket.apple += amount;
          appleRevenue += amount;
        } else if (event.store === "play_store") {
          bucket.android += amount;
          androidRevenue += amount;
        }
        byMonth.set(key, bucket);
      }

      const series = [...byMonth.entries()]
        .sort((first, second) => first[1].order - second[1].order)
        .slice(-6)
        .map(([month, values]) => ({
          month,
          apple: Math.round(values.apple * 100) / 100,
          android: Math.round(values.android * 100) / 100,
          total: Math.round((values.apple + values.android) * 100) / 100,
        }));

      const { count: activePaid, error: subscriptionError } = await admin
        .from("subscriptions")
        .select("*", { count: "exact", head: true })
        .in("status", ["active", "trialing"])
        .neq("plan", "free");
      if (subscriptionError) {
        throw new AppError(
          "internal_error",
          "Failed to count subscriptions",
          500,
        );
      }

      // Actual recurring value requires verified entitlement-level pricing and
      // period normalization. Catalog averages do not constitute MRR.
      const verifiedMrr: number | null = null;

      return json(
        {
          stats: {
            mrr: verifiedMrr,
            appleRevenue: Math.round(appleRevenue * 100) / 100,
            androidRevenue: Math.round(androidRevenue * 100) / 100,
            activePaid: activePaid ?? 0,
          },
          series,
        },
        200,
        publicCorsHeaders,
      );
    }

    throw new AppError(
      "not_found",
      `Unknown admin-subscriptions route: ${method} /${parts.join("/")}`,
      404,
    );
  } catch (error) {
    return errorResponse(error, publicCorsHeaders);
  }
}
