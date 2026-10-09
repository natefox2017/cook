// Developer: RecipePouch
// Purpose: Normalize and validate RevenueCat webhook values before persistence.

export const STATUS_MAP: Record<string, string> = {
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

export const STORE_MAP: Record<string, string> = {
  APP_STORE: "app_store",
  MAC_APP_STORE: "app_store",
  PLAY_STORE: "play_store",
  STRIPE: "stripe",
  PROMOTIONAL: "promotional",
  RC_BILLING: "rc_billing",
};

export const IGNORED = new Set(["TEST", "SUBSCRIBER_ALIAS", "TRANSFER"]);

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode("cookapp-rc-webhook"),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sa = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, enc.encode(a)),
  );
  const sb = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, enc.encode(b)),
  );
  if (sa.length !== sb.length) return false;
  let diff = 0;
  for (let i = 0; i < sa.length; i++) diff |= sa[i] ^ sb[i];
  return diff === 0;
}

export function msToIso(ms: unknown): string | null {
  if (ms == null) return null;
  const n = typeof ms === "number" ? ms : Number(ms);
  if (!Number.isFinite(n) || n <= 0) return null;
  return new Date(n).toISOString();
}

export function sanitize(
  event: Record<string, unknown>,
  rcEventId: string | null,
): Record<string, unknown> {
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
  for (const key of allow) {
    if (event[key] !== undefined) out[key] = event[key];
  }
  if (rcEventId) out.rc_event_id = rcEventId;
  return out;
}
