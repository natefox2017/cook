import type { AdminSession } from "./types.ts";

const object = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);
const string = (v: unknown) => typeof v === "string";
const number = (v: unknown) => typeof v === "number" && Number.isFinite(v);
const boolean = (v: unknown) => typeof v === "boolean";
const date = (v: unknown) => string(v) && Number.isFinite(Date.parse(v as string));
const nullable = (test: (v: unknown) => boolean, v: unknown) => v === null || test(v);
const list = (v: unknown, test: (v: unknown) => boolean) => Array.isArray(v) && v.every(test);
const fields = (v: unknown, names: string[], test: (v: unknown) => boolean) => object(v) && names.every(key => test(v[key]));
const oneOf = (v: unknown, values: string[]) => string(v) && values.includes(v as string);
const currency = (v: unknown) => string(v) && /^[A-Z]{3}$/.test(v as string);

function account(v: unknown): boolean {
  return fields(v, ["id", "username"], string) && object(v) &&
    oneOf(v.role, ["owner", "admin", "operator", "readonly"]) && boolean(v.mustChangePassword);
}

export function isAdminSession(v: unknown): v is AdminSession {
  return object(v) && typeof v.token === "string" && v.token.length > 0 && date(v.expiresAt) && account(v.admin);
}

function plan(v: unknown): boolean {
  return object(v) && fields(v, ["id", "planKey", "displayName", "productId"], string) &&
    number(v.price) && (v.price as number) >= 0 && currency(v.currency) && boolean(v.active) &&
    oneOf(v.platform, ["app_store", "play_store"]) && oneOf(v.billingPeriod, ["monthly", "yearly", "lifetime"]) &&
    nullable(string, v.description) && date(v.updatedAt);
}

function user(v: unknown): boolean {
  return object(v) && fields(v, ["id", "email", "displayName"], string) && date(v.createdAt) &&
    oneOf(v.subscription, ["free", "pro", "lifetime"]) && oneOf(v.status, ["active", "suspended", "deleted"]) &&
    oneOf(v.registrationProvider, ["apple", "google", "email", "unknown"]) && oneOf(v.deviceType, ["ios", "android", "web", "unknown"]) &&
    ["avatarUrl", "lastLoginIp", "subscriptionPlan", "subscriptionStatus"].every(k => nullable(string, v[k])) &&
    nullable(date, v.lastLoginAt) && nullable(x => oneOf(x, ["monthly", "yearly", "lifetime"]), v.subscriptionBillingPeriod);
}

function provider(v: unknown): boolean {
  return object(v) && fields(v, ["id", "name", "baseUrl", "model"], string) && boolean(v.active) && boolean(v.apiKeyConfigured) && date(v.updatedAt);
}

function dashboard(v: unknown): boolean {
  if (!object(v) || !object(v.stats) || !object(v.userBreakdown)) return false;
  const stats = v.stats;
  const amount = (x: unknown) => nullable(number, x);
  const breakdown = (x: unknown) => fields(x, ["key", "label"], string) && fields(x, ["value"], number);
  return fields(stats, ["totalUsers", "newUsersThisMonth", "activePaidUsers", "suspendedUsers", "paymentTransactions", "downloadsTotal", "downloadsIos", "downloadsAndroid", "incompleteRevenueEvents"], number) &&
    fields(stats, ["revenueTotal", "revenueMrr", "revenueApple", "revenueAndroid"], amount) &&
    nullable(currency, stats.revenueCurrency) && boolean(stats.revenueRowsTruncated) &&
    list(stats.revenueByCurrency, x => object(x) && currency(x.currency) && fields(x, ["appleRevenue", "androidRevenue", "total"], number)) &&
    ["byPlan", "byRegistrationType", "byDeviceType"].every(k => list(v.userBreakdown && (v.userBreakdown as Record<string, unknown>)[k], breakdown)) &&
    list(v.growth, x => fields(x, ["month"], string) && fields(x, ["users"], number)) &&
    list(v.series, x => fields(x, ["month"], string) && fields(x, ["users", "downloadsIos", "downloadsAndroid"], number) && fields(x, ["revenue", "revenueApple", "revenueAndroid"], amount));
}

// Check complete contracts at the boundary; malformed rows must not silently disappear.
export function validateAdminResponse(fn: string, path: string, method: string, v: unknown): void {
  const route = path.split("?")[0];
  let valid = true;
  if (fn === "admin-auth") {
    switch (route) {
      case "/bootstrap-status": valid = fields(v, ["initialized"], boolean); break;
      case "/session": valid = object(v) && account(v.admin); break;
      case "/bootstrap": case "/login": valid = isAdminSession(v) || (object(v) && v.factorRequired === true && fields(v, ["challengeToken"], string) && account(v.admin) && Array.isArray(v.methods) && v.methods.length > 0 && v.methods.every(x => oneOf(x, ["totp", "passkey"]))); break;
      case "/login-totp": case "/login-passkey-verify": case "/change-password": valid = isAdminSession(v); break;
      case "/login-passkey-options": case "/passkey-registration-options": valid = fields(v, ["challengeId"], string) && object(v) && object(v.options) && fields(v.options, ["challenge"], string); break;
      case "/totp-setup": valid = fields(v, ["secret", "otpauthUri"], string); break;
      case "/factors": valid = object(v) && object(v.totp) && boolean(v.totp.enabled) && nullable(date, v.totp.enabledAt) && list(v.passkeys, x => object(x) && fields(x, ["credential_id", "name"], string) && date(x.created_at) && nullable(date, x.last_used_at)); break;
      case "/login-events": valid = object(v) && number(v.total) && list(v.data, x => object(x) && fields(x, ["id"], string) && date(x.createdAt) && oneOf(x.method, ["password", "totp", "passkey", "bootstrap"]) && boolean(x.success) && ["ipAddress", "userAgent", "failureReason"].every(k => nullable(string, x[k]))); break;
      case "/logout": valid = object(v) && v.ok === true; break;
      case "/totp-verify": valid = object(v) && v.enabled === true; break;
      case "/totp-remove": case "/passkey-remove": valid = object(v) && v.removed === true; break;
      case "/passkey-registration-verify": valid = object(v) && v.created === true; break;
      default: valid = object(v); break;
    }
  } else if (fn === "admin-dashboard") valid = dashboard(v);
  else if (fn === "admin-users") {
    valid = route === "" ? object(v) && fields(v, ["total", "page", "pageSize"], number) && list(v.data, user)
      : user(v) && object(v) && list(v.payments, x => object(x) && fields(x, ["id", "eventType"], string) && date(x.purchasedAt) && nullable(number, x.amount) && ["productId", "store", "currency", "environment"].every(k => nullable(string, x[k])));
  } else if (fn === "admin-subscriptions") {
    if (route === "/plans" && method === "GET") valid = list(v, plan);
    else if (route.startsWith("/plans") && method !== "DELETE") valid = plan(v);
    else if (route.startsWith("/plans") && method === "DELETE") valid = object(v) && v.ok === true;
    else if (route === "/records") valid = list(v, x => object(x) && fields(x, ["id", "plan", "status"], string) && fields(x.user, ["id", "displayName", "email"], string) && nullable(y => oneOf(y, ["app_store", "play_store"]), x.platform) && nullable(string, x.productId) && nullable(number, x.amount) && nullable(currency, x.currency) && date(x.startDate) && nullable(date, x.expirationDate));
  } else if (fn === "admin-ai") {
    if (route === "/usage") valid = object(v) && fields(v.totals, ["requests", "inputTokens", "outputTokens", "totalTokens"], x => nullable(number, x)) &&
      object(v.totals) && ["cachedInputTokens", "averageLatencyMs"].every(k => v.totals && ((v.totals as Record<string, unknown>)[k] === undefined || nullable(number, (v.totals as Record<string, unknown>)[k]))) &&
      list(v.series, x => object(x) && date(x.date) && fields(x, ["requests", "inputTokens", "outputTokens", "totalTokens"], number)) &&
      list(v.byModel, x => fields(x, ["provider", "model"], string) && fields(x, ["requests", "totalTokens"], number));
    else if (route === "/providers" && method === "GET") valid = object(v) && list(v.data, provider);
    else if (route === "/providers/test") valid = fields(v, ["ok"], boolean) && object(v) && (v.message === undefined || string(v.message));
    else if (route.startsWith("/providers") && method === "DELETE") valid = object(v) && v.ok === true;
    // Save returns an acknowledgement, not the provider itself.
    else if (route.startsWith("/providers") && method !== "DELETE") valid = fields(v, ["id"], string);
  }
  if (!valid) throw new Error("Admin service returned incompatible data. Update the service and try again.");
}
