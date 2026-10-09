// Developer: gengyun
// Purpose: Verify the pinned health Auth client with synthetic credentials and no network access.

import { createServiceClient, requireUser } from "../_shared/auth.ts";
import { AppError } from "../_shared/errors.ts";

function expect(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("health rejects a missing bearer header before creating a client", async () => {
  try {
    await requireUser(new Request("https://example.invalid/health"));
    throw new Error("Missing authorization was accepted");
  } catch (error) {
    expect(
      error instanceof AppError && error.status === 401,
      "Expected unauthorized",
    );
  }
});

Deno.test("pinned Auth client verifies the user and keeps service credentials separate", async () => {
  const values: Record<string, string> = {
    SUPABASE_URL: "https://fixture.example.invalid",
    SUPABASE_ANON_KEY: "synthetic-anon-key",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-key",
  };
  const previous = new Map(
    Object.keys(values).map((key) => [key, Deno.env.get(key)]),
  );
  const originalFetch = globalThis.fetch;
  const calls: Array<
    { path: string; authorization: string | null; apiKey: string | null }
  > = [];
  try {
    for (const [key, value] of Object.entries(values)) Deno.env.set(key, value);
    globalThis.fetch = async (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const headers = new Headers(init?.headers);
      expect(
        url.origin === values.SUPABASE_URL,
        "Unexpected credential destination",
      );
      calls.push({
        path: url.pathname,
        authorization: headers.get("authorization"),
        apiKey: headers.get("apikey"),
      });
      if (url.pathname === "/auth/v1/user") {
        if (headers.get("authorization") === "Bearer synthetic-expired-token") {
          return Response.json({ message: "Invalid token" }, { status: 401 });
        }
        return Response.json({
          id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          aud: "authenticated",
          role: "authenticated",
          app_metadata: {},
          user_metadata: {},
          created_at: "2026-01-01T00:00:00Z",
        });
      }
      expect(url.pathname === "/rest/v1/fixture", "Unexpected API path");
      return Response.json([]);
    };

    const request = (token: string) =>
      new Request("https://example.invalid/health", {
        headers: { Authorization: `Bearer ${token}` },
      });
    const verified = await requireUser(request("synthetic-user-token"));
    expect(
      verified.user.id === "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "User verification failed",
    );
    expect(
      calls[0].authorization === "Bearer synthetic-user-token",
      "User bearer was replaced",
    );
    expect(
      calls[0].apiKey === values.SUPABASE_ANON_KEY,
      "User verification used a privileged key",
    );

    const { error } = await createServiceClient().from("fixture").select("id");
    expect(error === null, "Service client API shape changed");
    expect(
      calls[1].authorization === `Bearer ${values.SUPABASE_SERVICE_ROLE_KEY}`,
      "Service bearer missing",
    );
    expect(
      calls[1].apiKey === values.SUPABASE_SERVICE_ROLE_KEY,
      "Service API key missing",
    );

    try {
      await requireUser(request("synthetic-expired-token"));
      throw new Error("Expired authorization was accepted");
    } catch (error) {
      expect(
        error instanceof AppError && error.status === 401,
        "Expected invalid user rejection",
      );
    }
    expect(
      calls.length === 3,
      "Unexpected implicit refresh or network request",
    );
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of previous) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
