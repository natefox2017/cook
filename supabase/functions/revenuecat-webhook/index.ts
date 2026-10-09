// Developer: gengyun
// Purpose: Receive authenticated RevenueCat events and sync subscription state.

import "jsr:@supabase/functions-js@2.117.3/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.117.3";
import {
  IGNORED,
  json,
  msToIso,
  readBody,
  sanitize,
  STATUS_MAP,
  STORE_MAP,
  timingSafeEqual,
  UUID_RE,
  verifySignature,
} from "./webhook.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
const SIGNING_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SIGNING_SECRET") ?? "";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE || !WEBHOOK_SECRET) {
    return json({ error: "server_misconfigured" }, 500);
  }

  const auth = req.headers.get("Authorization") ?? "";
  const ok = await timingSafeEqual(auth, `Bearer ${WEBHOOK_SECRET}`);
  if (!ok) return json({ error: "unauthorized" }, 401);

  let bytes: Uint8Array;
  try {
    bytes = await readBody(req);
  } catch (error) {
    const tooLarge = error instanceof Error &&
      error.message === "payload_too_large";
    return json(
      { error: tooLarge ? "payload_too_large" : "invalid_body" },
      tooLarge ? 413 : 400,
    );
  }
  if (
    SIGNING_SECRET && !await verifySignature(
      bytes,
      req.headers.get("X-RevenueCat-Webhook-Signature") ?? "",
      SIGNING_SECRET,
    )
  ) {
    return json({ error: "invalid_signature" }, 401);
  }

  let body;
  try {
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "missing_event" }, 400);
  }
  const event = body.event as Record<string, unknown> | undefined;
  if (!event || typeof event !== "object" || Array.isArray(event)) {
    return json({ error: "missing_event" }, 400);
  }

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
  const userId = (UUID_RE.test(appUserId)
    ? appUserId
    : UUID_RE.test(originalId)
    ? originalId
    : "").toLowerCase();
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
  const rcEventId = typeof event.id === "string" ? event.id.trim() : "";
  // Provider IDs are required for atomic database deduplication across workers.
  if (!rcEventId || rcEventId.length > 256) {
    return json({ error: "invalid_event_id" }, 400);
  }
  const expiresAt = msToIso(event.expiration_at_ms);
  const willRenew = typeof event.is_auto_renewing === "boolean"
    ? event.is_auto_renewing
    : null;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  {
    const { data: existing, error: lookupError } = await supabase
      .from("purchase_events")
      .select("id,user_id")
      .eq("rc_event_id", rcEventId)
      .limit(1);
    if (lookupError) {
      return json({ error: "lookup_failed" }, 500);
    }
    if (existing && existing.length > 0) {
      if (existing[0].user_id !== userId) {
        return json({
          error: "event_owner_mismatch",
        }, 409);
      }
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
    // Database diagnostic messages can contain payload values; log only the code.
    console.error("revenuecat_upsert_failed", { code: error.code });
    if (error.code === "42501") {
      return json(
        { error: "event_owner_mismatch" },
        409,
      );
    }
    if (error.code === "23503") {
      return json({ received: true, skipped: true, reason: "user_not_found" });
    }
    return json({ error: "upsert_failed" }, 500);
  }

  return json({ received: true, processed: true, type, subscription: data });
});
