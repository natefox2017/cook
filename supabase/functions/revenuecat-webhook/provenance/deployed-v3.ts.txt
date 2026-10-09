// RevenueCat → Supabase subscription sync (server-to-server).
// Auth: Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>
// Set secret: supabase secrets set REVENUECAT_WEBHOOK_SECRET=... --project-ref semsjyrqjnumpvanibip

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";

const STATUS_MAP: Record<string, string> = {
  INITIAL_PURCHASE: "active",
  RENEWAL: "active",
  PRODUCT_CHANGE: "active",
  UNCANCELLATION: "active",
  NON_RENEWING_PURCHASE: "active",
  SUBSCRIPTION_EXTENDED: "active",
  TEMPORARY_ENTITLEMENT_GRANT: "active",
  CANCELLATION: "cancelled",
  EXPIRATION: "expired",
  BILLING_ISSUE: "billing_issue",
};

const STORE_MAP: Record<string, string> = {
  APP_STORE: "app_store",
  MAC_APP_STORE: "app_store",
  PLAY_STORE: "play_store",
  STRIPE: "stripe",
  PROMOTIONAL: "promotional",
  RC_BILLING: "rc_billing",
};

const IGNORED = new Set(["TEST", "SUBSCRIBER_ALIAS", "TRANSFER"]);

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode("cookapp-rc-webhook"),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sa = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(a)));
  const sb = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(b)));
  if (sa.length !== sb.length) return false;
  let diff = 0;
  for (let i = 0; i < sa.length; i++) diff |= sa[i] ^ sb[i];
  return diff === 0;
}

function msToIso(ms: unknown): string | null {
  if (ms == null) return null;
  const n = typeof ms === "number" ? ms : Number(ms);
  if (!Number.isFinite(n) || n <= 0) return null;
  return new Date(n).toISOString();
}

function sanitize(event: Record<string, unknown>, rcEventId: string | null) {
  const allow = [
    "type",
    "id",
    "product_id",
    "store",
    "environment",
    "purchased_at_ms",
    "expiration_at_ms",
    "event_timestamp_ms",
    "entitlement_ids",
    "period_type",
    "presented_offering_id",
    "currency",
    "price",
    "price_in_purchased_currency",
    "country_code",
    "is_trial_conversion",
    "is_family_share",
    "cancellation_reason",
  ];
  const out: Record<string, unknown> = {};
  for (const k of allow) {
    if (event[k] !== undefined) out[k] = event[k];
  }
  if (rcEventId) out.rc_event_id = rcEventId;
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE || !WEBHOOK_SECRET) {
    return json({ error: "server_misconfigured" }, 500);
  }

  const auth = req.headers.get("Authorization") ?? "";
  const ok = await timingSafeEqual(auth, `Bearer ${WEBHOOK_SECRET}`);
  if (!ok) return json({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const event = body.event as Record<string, unknown> | undefined;
  if (!event) return json({ error: "missing_event" }, 400);

  const type = String(event.type ?? "").toUpperCase();
  if (IGNORED.has(type)) return json({ received: true, ignored: true, type });

  const status = STATUS_MAP[type];
  if (!status) return json({ received: true, ignored: true, reason: "unknown_type", type });

  const appUserId = String(event.app_user_id ?? "").trim();
  const originalId = String(event.original_app_user_id ?? "").trim();
  const userId = UUID_RE.test(appUserId)
    ? appUserId
    : UUID_RE.test(originalId)
    ? originalId
    : "";
  if (!userId) {
    return json({ received: true, skipped: true, reason: "unresolvable_user_id" });
  }

  const productId = String(event.product_id ?? "").trim();
  const store = STORE_MAP[String(event.store ?? "").toUpperCase()] ?? "unknown";
  const environment =
    String(event.environment ?? "PRODUCTION").toUpperCase() === "SANDBOX"
      ? "sandbox"
      : "production";
  const entitlementIds = Array.isArray(event.entitlement_ids)
    ? event.entitlement_ids.map(String)
    : [];
  const entitlementId = entitlementIds[0] ?? "pro";
  const rcEventId = String(event.id ?? "").trim() || null;
  const expiresAt = msToIso(event.expiration_at_ms);
  const willRenew =
    typeof event.is_auto_renewing === "boolean"
      ? event.is_auto_renewing
      : null;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  if (rcEventId) {
    const { data: existing } = await supabase
      .from("purchase_events")
      .select("id")
      .eq("rc_event_id", rcEventId)
      .limit(1);
    if (existing && existing.length > 0) {
      return json({ received: true, already_processed: true, rc_event_id: rcEventId });
    }
  }

  const { data, error } = await supabase.rpc("upsert_subscription_from_revenuecat", {
    p_user_id: userId,
    p_event_type: type,
    p_product_id: productId || null,
    p_entitlement_id: entitlementId,
    p_status: status,
    p_store: store,
    p_environment: environment,
    p_expires_at: expiresAt,
    p_will_renew: willRenew,
    p_revenuecat_app_user_id: appUserId || userId,
    p_rc_event_id: rcEventId,
    p_raw_event: sanitize(event, rcEventId),
  });

  if (error) {
    console.error("upsert failed", error.message);
    if (error.message.includes("foreign key")) {
      return json({ received: true, skipped: true, reason: "user_not_found" });
    }
    return json({ error: "upsert_failed" }, 500);
  }

  return json({ received: true, processed: true, type, subscription: data });
});
