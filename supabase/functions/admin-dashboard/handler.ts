// Developer: RecipePouch
// Purpose: Expose owner-only aggregate user, subscription, payment, and download statistics.
// Production baseline: admin-dashboard v3, downloaded entrypoint SHA-256 508bd852b227a8367fe7cf6c2776f3e74d0d2fdd6a3d77ee8700eaef71169237.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";
import { handleCors, publicCorsHeaders } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { requireAdminSession } from "../_shared/admin-session.ts";
import { requireDashboardRole } from "./access.ts";
import { utcMonthKey, displayUTCMonth } from "../_shared/monthBuckets.ts";
import { RecordedRevenueLedger } from "../_shared/recordedRevenue.ts";

const PAID_TYPES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "NON_RENEWING_PURCHASE",
  "PRODUCT_CHANGE",
]);

function monthOrder(iso: string): number {
  const d = new Date(iso);
  return d.getUTCFullYear() * 12 + d.getUTCMonth();
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function mapPlan(
  plan: unknown,
  productId: unknown,
): "free" | "pro" | "lifetime" {
  const p = String(plan ?? "");
  if (p === "pro" || p === "lifetime" || p === "free") return p;
  const pid = String(productId ?? "").toLowerCase();
  if (pid.includes("lifetime")) return "lifetime";
  if (pid.includes("pro") || pid.includes("month") || pid.includes("year")) {
    return "pro";
  }
  return "free";
}

function eventAmount(raw: Record<string, unknown> | null): number {
  if (!raw) return 0;
  const amount = Number(raw.price_in_purchased_currency ?? raw.price ?? 0);
  return Number.isFinite(amount) ? amount : 0;
}

type AdminSession = Awaited<ReturnType<typeof requireAdminSession>>;
type AdminClient = ReturnType<typeof createServiceClient>;

export interface AdminDashboardDependencies {
  requireAdminSession: (req: Request) => Promise<AdminSession>;
  createServiceClient: () => AdminClient;
}

const productionDependencies: AdminDashboardDependencies = {
  requireAdminSession,
  createServiceClient,
};

export async function handleRequest(
  req: Request,
  dependencies: AdminDashboardDependencies = productionDependencies,
): Promise<Response> {
  const cors = handleCors(req, "public");
  if (cors) return cors;

  try {
    if (req.method.toUpperCase() !== "GET") {
      throw new AppError("method_not_allowed", "Only GET is supported", 405);
    }
    const session = await dependencies.requireAdminSession(req);
    requireDashboardRole(session.role);

    const admin = dependencies.createServiceClient();
    const now = new Date();
    const monthStart = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    )
      .toISOString();

    const [
      { count: totalUsers },
      { count: newUsersThisMonth },
      { count: suspendedUsers },
      { count: totalRecipes },
      { count: collections },
      { count: activePaidUsers },
      { data: profiles },
      { data: subscriptions },
      { data: purchaseEvents, error: purchaseError },
      { data: downloadRows, error: downloadError },
      { data: recentProfiles },
      { data: recentRecipes },
    ] = await Promise.all([
      admin.from("profiles").select("*", { count: "exact", head: true }),
      admin
        .from("profiles")
        .select("*", { count: "exact", head: true })
        .gte("created_at", monthStart),
      admin
        .from("profiles")
        .select("*", { count: "exact", head: true })
        .eq("account_status", "suspended"),
      admin.from("recipes").select("*", { count: "exact", head: true }),
      admin.from("collections").select("*", { count: "exact", head: true }),
      admin
        .from("subscriptions")
        .select("*", { count: "exact", head: true })
        .in("status", ["active", "trialing"])
        .neq("plan", "free"),
      admin.from("profiles").select("registration_type, device_type"),
      admin.from("subscriptions").select("user_id, plan, product_id, status"),
      admin
        .from("purchase_events")
        .select(
          "id, user_id, event_type, store, raw_event, created_at, product_id",
        )
        .order("created_at", { ascending: false })
        .limit(5000),
      admin
        .from("app_download_stats")
        .select("platform, year_month, downloads")
        .order("year_month", { ascending: true }),
      admin
        .from("profiles")
        .select(
          "id, email, display_name, registration_type, device_type, registration_ip, created_at",
        )
        .order("created_at", { ascending: false })
        .limit(5),
      admin
        .from("recipes")
        .select("id, title, user_id, created_at")
        .order("created_at", { ascending: false })
        .limit(5),
    ]);

    if (purchaseError) {
      throw new AppError(
        "internal_error",
        "Failed to load payment events",
        500,
      );
    }
    if (downloadError) {
      throw new AppError(
        "internal_error",
        "Failed to load download statistics",
        500,
      );
    }

    const byRegistrationType = {
      apple: 0,
      google: 0,
      email: 0,
      unknown: 0,
    };
    const byDeviceType = {
      iphone: 0,
      ipad: 0,
      android: 0,
      web: 0,
      unknown: 0,
    };
    for (const row of profiles ?? []) {
      const reg = String(row.registration_type ?? "unknown");
      if (reg in byRegistrationType) {
        byRegistrationType[reg as keyof typeof byRegistrationType] += 1;
      } else {
        byRegistrationType.unknown += 1;
      }
      const device = String(row.device_type ?? "unknown");
      if (device in byDeviceType) {
        byDeviceType[device as keyof typeof byDeviceType] += 1;
      } else {
        byDeviceType.unknown += 1;
      }
    }

    const byPlan = { free: 0, pro: 0, lifetime: 0 };
    for (const row of subscriptions ?? []) {
      byPlan[mapPlan(row.plan, row.product_id)] += 1;
    }
    const knownSubs = (subscriptions ?? []).length;
    byPlan.free += Math.max((totalUsers ?? 0) - knownSubs, 0);

    let paymentTransactions = 0;
    const recordedRevenue = new RecordedRevenueLedger();
    const usersByMonth = new Map<string, { count: number; order: number }>();
    const recipesByMonth = new Map<string, { count: number; order: number }>();

    const { data: allProfilesForGrowth } = await admin
      .from("profiles")
      .select("created_at")
      .order("created_at", { ascending: true })
      .limit(10000);
    for (const row of allProfilesForGrowth ?? []) {
      const created = String(row.created_at);
      const key = utcMonthKey(created);
      const order = monthOrder(created);
      const bucket = usersByMonth.get(key) ?? { count: 0, order };
      bucket.count += 1;
      usersByMonth.set(key, bucket);
    }

    const { data: allRecipesForGrowth } = await admin
      .from("recipes")
      .select("created_at")
      .order("created_at", { ascending: true })
      .limit(10000);
    for (const row of allRecipesForGrowth ?? []) {
      const created = String(row.created_at);
      const key = utcMonthKey(created);
      const order = monthOrder(created);
      const bucket = recipesByMonth.get(key) ?? { count: 0, order };
      bucket.count += 1;
      recipesByMonth.set(key, bucket);
    }

    const eventsAsc = [...(purchaseEvents ?? [])].reverse();
    for (const event of eventsAsc) {
      const type = String(event.event_type ?? "").toUpperCase();
      if (!PAID_TYPES.has(type)) continue;
      paymentTransactions++;
      recordedRevenue.record(
        event.raw_event,
        event.store,
        utcMonthKey(String(event.created_at)),
      );
    }
    // Currency totals are comparable only if every source row is usable and
    // the result set is below its unverified pagination cap.
    const monetary = recordedRevenue.summary((purchaseEvents ?? []).length === 5000);

    let downloadsIos = 0;
    let downloadsAndroid = 0;
    const downloadsByMonth = new Map<
      string,
      { ios: number; android: number; order: number }
    >();
    for (const row of downloadRows ?? []) {
      const ym = String(row.year_month);
      const key = utcMonthKey(ym);
      const order = monthOrder(ym);
      const bucket = downloadsByMonth.get(key) ?? { ios: 0, android: 0, order };
      const count = Number(row.downloads) || 0;
      if (row.platform === "ios") {
        bucket.ios += count;
        downloadsIos += count;
      } else if (row.platform === "android") {
        bucket.android += count;
        downloadsAndroid += count;
      }
      downloadsByMonth.set(key, bucket);
    }

    const allOrders = new Map<string, number>();
    for (const [k, v] of usersByMonth) allOrders.set(k, v.order);
    for (const [k, v] of recipesByMonth) allOrders.set(k, v.order);
    for (const month of recordedRevenue.monthKeys()) {
      allOrders.set(month, monthOrder(month + "-01T00:00:00Z"));
    }
    for (const [k, v] of downloadsByMonth) allOrders.set(k, v.order);

    const orderedMonths = [...allOrders.entries()]
      .sort((a, b) => a[1] - b[1])
      .slice(-6)
      .map(([month]) => month);

    let cumUsers = 0;
    let cumRecipes = 0;
    const minOrder = orderedMonths.length
      ? Math.min(...orderedMonths.map((m) => allOrders.get(m)!))
      : 0;
    for (const [month, v] of usersByMonth) {
      if ((allOrders.get(month) ?? 0) < minOrder) cumUsers += v.count;
    }
    for (const [month, v] of recipesByMonth) {
      if ((allOrders.get(month) ?? 0) < minOrder) cumRecipes += v.count;
    }

    const series = orderedMonths.map((month) => {
      cumUsers += usersByMonth.get(month)?.count ?? 0;
      cumRecipes += recipesByMonth.get(month)?.count ?? 0;
      const rev = recordedRevenue.monthly(month, monetary.currency);
      const dl = downloadsByMonth.get(month) ??
        { ios: 0, android: 0, order: 0 };
      return {
        month,
        users: cumUsers,
        recipes: cumRecipes,
        revenue: rev ? round2(rev.apple + rev.android) : null,
        revenueApple: rev?.apple ?? null,
        revenueAndroid: rev?.android ?? null,
        downloadsIos: dl.ios,
        downloadsAndroid: dl.android,
      };
    });

    const growth = series.map((p) => ({
      month: p.month,
      users: p.users,
      recipes: p.recipes,
    }));

    // No verified entitlement-level monthly recurring amount is available.
    // A catalog-price average across trial/yearly/lifetime users is not MRR.
    const revenueMrr: number | null = null;

    const recentPaid = (purchaseEvents ?? [])
      .filter((e) => PAID_TYPES.has(String(e.event_type ?? "").toUpperCase()))
      .slice(0, 8);

    const payUserIds = [
      ...new Set(recentPaid.map((e) => e.user_id).filter(Boolean)),
    ] as string[];
    const labelByUser = new Map<string, string>();
    if (payUserIds.length) {
      const { data: payProfiles } = await admin
        .from("profiles")
        .select("id, email, display_name")
        .in("id", payUserIds);
      for (const p of payProfiles ?? []) {
        labelByUser.set(
          p.id,
          String(p.display_name || p.email || p.id.slice(0, 8)),
        );
      }
    }

    const recentPayments = recentPaid.map((event) => {
      const raw = (event.raw_event ?? {}) as Record<string, unknown>;
      const amount = eventAmount(raw);
      return {
        id: event.id,
        userLabel: labelByUser.get(String(event.user_id)) ?? "Unknown user",
        eventType: String(event.event_type ?? ""),
        store: String(event.store ?? "unknown"),
        // Do not invent USD when the original event omits its currency.
        amount: amount > 0 && /^[A-Z]{3}$/.test(String(raw.currency ?? raw.currency_code ?? "").trim().toUpperCase())
          ? round2(amount) : null,
        currency: /^[A-Z]{3}$/.test(String(raw.currency ?? raw.currency_code ?? "").trim().toUpperCase())
          ? String(raw.currency ?? raw.currency_code).trim().toUpperCase() : null,
        createdAt: String(event.created_at),
      };
    });

    type Activity = {
      id: string;
      type:
        | "user"
        | "recipe"
        | "collection"
        | "subscription"
        | "payment"
        | "download";
      title: string;
      subtitle: string;
      createdAt: string;
    };
    const recent: Activity[] = [];

    for (const p of recentProfiles ?? []) {
      recent.push({
        id: `user_${p.id}`,
        type: "user",
        title: `${p.display_name || p.email || "User"} joined`,
        subtitle: [
          p.registration_type ?? "unknown",
          p.device_type ?? "unknown",
          p.registration_ip ?? "",
        ]
          .filter(Boolean)
          .join(" · "),
        createdAt: String(p.created_at),
      });
    }

    const recipeOwnerIds = [
      ...new Set((recentRecipes ?? []).map((r) => r.user_id).filter(Boolean)),
    ] as string[];
    const recipeOwnerLabel = new Map<string, string>();
    if (recipeOwnerIds.length) {
      const { data: owners } = await admin
        .from("profiles")
        .select("id, email, display_name")
        .in("id", recipeOwnerIds);
      for (const o of owners ?? []) {
        recipeOwnerLabel.set(o.id, String(o.email || o.display_name || o.id));
      }
    }
    for (const r of recentRecipes ?? []) {
      recent.push({
        id: `recipe_${r.id}`,
        type: "recipe",
        title: String(r.title ?? "Recipe"),
        subtitle: `Recipe created by ${
          recipeOwnerLabel.get(r.user_id) ?? "unknown"
        }`,
        createdAt: String(r.created_at),
      });
    }

    for (const pay of recentPayments.slice(0, 3)) {
      recent.push({
        id: `payment_${pay.id}`,
        type: "payment",
        title: `${pay.eventType}`,
        subtitle: `${pay.userLabel} · ${pay.store} · ${
          pay.amount == null ? "—" : `$${pay.amount}`
        }`,
        createdAt: pay.createdAt,
      });
    }

    if ((downloadRows ?? []).length) {
      const latest = [...(downloadRows ?? [])].sort((a, b) =>
        String(b.year_month).localeCompare(String(a.year_month))
      )[0];
      recent.push({
        id: `download_${latest.platform}_${latest.year_month}`,
        type: "download",
        title: `${latest.platform === "ios" ? "iOS" : "Android"} downloads`,
        subtitle: `${latest.downloads} installs · ${
          displayUTCMonth(String(latest.year_month))
        }`,
        createdAt: String(latest.year_month),
      });
    }

    recent.sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));

    return json(
      {
        stats: {
          totalUsers: totalUsers ?? 0,
          totalRecipes: totalRecipes ?? 0,
          collections: collections ?? 0,
          favorites: 0,
          newUsersThisMonth: newUsersThisMonth ?? 0,
          activePaidUsers: activePaidUsers ?? 0,
          suspendedUsers: suspendedUsers ?? 0,
          revenueTotal: monetary.total,
          revenueMrr,
          revenueApple: monetary.appleRevenue,
          revenueAndroid: monetary.androidRevenue,
          revenueCurrency: monetary.currency,
          revenueByCurrency: monetary.byCurrency,
          incompleteRevenueEvents: monetary.incompleteEvents,
          revenueRowsTruncated: monetary.sourceRowsTruncated,
          paymentTransactions,
          downloadsTotal: downloadsIos + downloadsAndroid,
          downloadsIos,
          downloadsAndroid,
        },
        growth,
        series,
        userBreakdown: {
          byRegistrationType: [
            { key: "apple", label: "Apple", value: byRegistrationType.apple },
            {
              key: "google",
              label: "Google",
              value: byRegistrationType.google,
            },
            { key: "email", label: "Email", value: byRegistrationType.email },
            {
              key: "unknown",
              label: "Unknown",
              value: byRegistrationType.unknown,
            },
          ],
          byDeviceType: [
            { key: "iphone", label: "iPhone", value: byDeviceType.iphone },
            { key: "ipad", label: "iPad", value: byDeviceType.ipad },
            { key: "android", label: "Android", value: byDeviceType.android },
            { key: "web", label: "Web", value: byDeviceType.web },
            { key: "unknown", label: "Unknown", value: byDeviceType.unknown },
          ],
          byPlan: [
            { key: "free", label: "Free", value: byPlan.free },
            { key: "pro", label: "Pro", value: byPlan.pro },
            { key: "lifetime", label: "Lifetime", value: byPlan.lifetime },
          ],
        },
        recent: recent.slice(0, 8),
        recentPayments,
      },
      200,
      publicCorsHeaders,
    );
  } catch (err) {
    return errorResponse(err, publicCorsHeaders);
  }
}
