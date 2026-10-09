// Developer: RecipePouch
// Purpose: Receive authenticated RevenueCat events and sync subscription state.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.117.3";
import {
  IGNORED,
  json,
  msToIso,
  sanitize,
  STATUS_MAP,
  STORE_MAP,
  timingSafeEqual,
  UUID_RE,
} from "./webhook.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";

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
  if (!status) {
    return json({
      received: true,
      ignored: true,
      reason: "unknown_type",
      type,
    });
  }

  const appUserId = String(event.app_user_id ?? "").trim();
  const originalId = String(event.original_app_user_id ?? "").trim();
  const userId = UUID_RE.test(appUserId)
    ? appUserId
    : UUID_RE.test(originalId)
    ? originalId
    : "";
  if (!userId) {
    return json({
      received: true,
      skipped: true,
      reason: "unresolvable_user_id",
    });
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
  const willRenew = typeof event.is_auto_renewing === "boolean"
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
      return json({
        received: true,
        already_processed: true,
        rc_event_id: rcEventId,
      });
    }
  }

  const { data, error } = await supabase.rpc(
    "upsert_subscription_from_revenuecat",
    {
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
    },
  );

  if (error) {
    console.error("upsert failed", error.message);
    if (error.message.includes("foreign key")) {
      return json({ received: true, skipped: true, reason: "user_not_found" });
    }
    return json({ error: "upsert_failed" }, 500);
  }

  return json({ received: true, processed: true, type, subscription: data });
});
