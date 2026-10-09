import type {
  AdminSession,
  AdminUserDetail,
  AdminUserPage,
  DashboardData,
  LLMProvider,
  LLMProviderInput,
  LLMUsage,
  LLMUsageRange,
  RevenueData,
  SubscriptionPlan,
  SubscriptionRecord,
} from "./types";

const functionsBase = import.meta.env.VITE_ADMIN_FUNCTIONS_URL?.replace(/\/$/, "");
const apiKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const isConfigured = Boolean(functionsBase && apiKey);

export class AdminApiError extends Error {
  readonly status: number;
  readonly code?: string;

  constructor(
    message: string,
    status: number,
    code?: string,
  ) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

async function request<T>(
  functionName: string,
  path: string,
  token: string | undefined,
  options: { method?: string; body?: unknown; headers?: Record<string, string> } = {},
): Promise<T> {
  if (!functionsBase || !apiKey) {
    throw new AdminApiError("Add the Supabase function URL and publishable key to admin/.env.local.", 0);
  }

  const response = await fetch(`${functionsBase}/${functionName}${path}`, {
    method: options.method ?? "GET",
    headers: {
      apikey: apiKey,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...options.headers,
    },
    ...(options.body ? { body: JSON.stringify(options.body) } : {}),
    cache: "no-store",
  });

  const result = await response.json().catch(() => null);
  if (!response.ok) {
    const message = typeof result?.message === "string"
      ? result.message
      : typeof result?.error?.message === "string"
      ? result.error.message
      : typeof result?.error_description === "string"
      ? result.error_description
      : typeof result?.error === "string"
      ? result.error
      : `Request failed (${response.status})`;
    throw new AdminApiError(message, response.status, result?.code ?? result?.error?.code);
  }
  return result as T;
}

export const adminApi = {
  login(username: string, password: string) {
    return request<AdminSession>("admin-auth", "/login", undefined, {
      method: "POST",
      body: { username, password },
    });
  },
  bootstrap(username: string, newPassword: string, bootstrapToken: string, currentPassword?: string) {
    return request<AdminSession>("admin-auth", "/bootstrap", undefined, {
      method: "POST",
      headers: { Authorization: `Bearer ${bootstrapToken}` },
      body: { username, newPassword, ...(currentPassword ? { currentPassword } : {}) },
    });
  },
  session(token: string) {
    return request<{ admin: AdminSession["admin"] }>("admin-auth", "/session", token);
  },
  logout(token: string) {
    return request<{ ok: boolean }>("admin-auth", "/logout", token, { method: "POST" });
  },
  changePassword(token: string, currentPassword: string, newPassword: string) {
    return request<AdminSession>("admin-auth", "/change-password", token, {
      method: "POST",
      body: { currentPassword, newPassword },
    });
  },
  dashboard(token: string) {
    return request<DashboardData>("admin-dashboard", "", token);
  },
  users(token: string, query: URLSearchParams) {
    return request<AdminUserPage>("admin-users", `?${query.toString()}`, token);
  },
  user(token: string, id: string) {
    return request<AdminUserDetail>("admin-users", `/${encodeURIComponent(id)}`, token);
  },
  plans(token: string) {
    return request<SubscriptionPlan[]>("admin-subscriptions", "/plans", token);
  },
  records(token: string, platform?: "app_store" | "play_store") {
    const query = platform ? `?platform=${platform}` : "";
    return request<SubscriptionRecord[]>("admin-subscriptions", `/records${query}`, token);
  },
  revenue(token: string, platform?: "app_store" | "play_store") {
    const query = platform ? `?platform=${platform}` : "";
    return request<RevenueData>("admin-subscriptions", `/revenue${query}`, token);
  },
  savePlan(token: string, input: Omit<SubscriptionPlan, "id" | "updatedAt">, id?: string) {
    return request<SubscriptionPlan>("admin-subscriptions", id ? `/plans/${encodeURIComponent(id)}` : "/plans", token, {
      method: id ? "PUT" : "POST",
      body: {
        planKey: input.planKey,
        displayName: input.displayName,
        platform: input.platform,
        productId: input.productId,
        price: input.price,
        currency: input.currency,
        billingPeriod: input.billingPeriod,
        active: input.active,
        description: input.description,
      },
    });
  },
  deletePlan(token: string, id: string) {
    return request<{ ok: boolean }>("admin-subscriptions", `/plans/${encodeURIComponent(id)}`, token, { method: "DELETE" });
  },
  llmProviders(token: string) {
    return request<{ data: LLMProvider[] }>("admin-ai", "/providers", token);
  },
  saveLlmProvider(token: string, input: LLMProviderInput, id?: string) {
    return request<LLMProvider>("admin-ai", id ? `/providers/${encodeURIComponent(id)}` : "/providers", token, {
      method: id ? "PUT" : "POST",
      body: input,
    });
  },
  deleteLlmProvider(token: string, id: string) {
    return request<{ ok: boolean }>("admin-ai", `/providers/${encodeURIComponent(id)}`, token, { method: "DELETE" });
  },
  llmUsage(token: string, range: LLMUsageRange) {
    return request<LLMUsage>("admin-ai", `/usage?range=${range}`, token);
  },
};

export function handleExpiredSession(error: unknown, onAuthExpired: () => void) {
  if (error instanceof AdminApiError && error.status === 401) onAuthExpired();
}
