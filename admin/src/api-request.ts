import { isSecureApiEndpoint } from "./api-endpoint.ts";

export class AdminApiError extends Error {
  readonly status: number;
  readonly code?: string;

  constructor(message: string, status: number, code?: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export async function sendAdminRequest(
  base: string | undefined,
  apiKey: string | undefined,
  origin: string,
  path: string,
  token: string | undefined,
  options: { method?: string; body?: unknown; headers?: Record<string, string>; redirect?: RequestRedirect } = {},
): Promise<unknown> {
  if (!apiKey || !isSecureApiEndpoint(base, origin)) {
    throw new AdminApiError("Configure an HTTPS admin API endpoint and publishable key. Credentials were not sent.", 0);
  }
  const signal = AbortSignal.timeout(30_000);
  try {
    const response = await fetch(`${base!.replace(/\/$/, "")}/${path}`, {
      method: options.method ?? "GET",
      headers: {
        apikey: apiKey,
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(options.body !== undefined ? { "Content-Type": "application/json" } : {}),
        ...options.headers,
      },
      ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {}),
      redirect: "error",
      signal,
      cache: "no-store",
    });
    const result = await response.json().catch(() => null);
    if (!response.ok) {
      const message = typeof result?.message === "string" ? result.message
        : typeof result?.error?.message === "string" ? result.error.message
        : `Request failed (${response.status}).`;
      throw new AdminApiError(message, response.status, result?.code ?? result?.error?.code);
    }
    if (result === null) throw new AdminApiError("Admin service returned an invalid JSON response. Try again or update the service.", response.status);
    return result;
  } catch (error) {
    if (error instanceof AdminApiError) throw error;
    throw new AdminApiError(signal.aborted
      ? "Admin request timed out. Try again."
      : "Unable to reach the admin service securely. Check the connection and try again.", 0);
  }
}

export function handleExpiredSession(error: unknown, onAuthExpired: () => void) {
  if (!(error instanceof AdminApiError) || error.status !== 401) return;
  // Legacy deployments used unauthorized for both expired sessions and bad factor codes.
  if (error.code === "session_expired" || /^(Invalid or expired admin session|Invalid admin session|Invalid administrator role|Missing or invalid Authorization header|Missing bearer token)$/.test(error.message)) {
    onAuthExpired();
  }
}
